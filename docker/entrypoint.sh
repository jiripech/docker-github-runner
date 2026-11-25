#!/bin/bash
set -e

# Validate environment variables
if [ -z "$GITHUB_URL" ]; then
    echo "Error: GITHUB_URL is not set"
    exit 1
fi

if [ -z "$GH_PAT" ]; then
    echo "Error: GH_PAT is not set (required for multi-runner auto-registration)"
    exit 1
fi

if [ -z "$RUNNER_NAME_PREFIX" ]; then
    echo "Error: RUNNER_NAME_PREFIX is not set"
    exit 1
fi

# Set defaults
RUNNER_LABELS=${RUNNER_LABELS:-default}
RUNNER_WORKDIR_BASE=${RUNNER_WORKDIR:-_work}
FAIL_FAST=${FAIL_FAST:-true}  # Set to "false" to skip failed repos and continue

# Base runner installation directory (where config.sh, run.sh, bin/ are located - read-only from image)
RUNNER_BASE_DIR="/home/runner"
# Persistent data directory for runner configurations (mounted volume)
RUNNER_DATA_DIR="/data"

# Start SSH daemon
echo "Starting SSH Daemon..."
sudo /usr/sbin/sshd

# Ensure data directory exists and is writable
mkdir -p "$RUNNER_DATA_DIR"
cd "$RUNNER_DATA_DIR"

# Handle UNREGISTER_TOKENS - unregister runners using provided tokens (legacy)
# Also supports UNREGISTER_RUNNERS="repo1,repo2" to remove by name via API
if [ -n "$UNREGISTER_TOKENS" ] || [ -n "$UNREGISTER_RUNNERS" ]; then
    echo "=========================================="
    echo "Unregistering runners..."
    echo "=========================================="

    # First, try token-based removal (legacy)
    # Run from RUNNER_BASE_DIR where config.sh exists
    if [ -n "$UNREGISTER_TOKENS" ]; then
        IFS=',' read -ra UNREGISTER_TOKEN_ARRAY <<< "$UNREGISTER_TOKENS"
        cd "$RUNNER_BASE_DIR"
        for token in "${UNREGISTER_TOKEN_ARRAY[@]}"; do
            token=$(echo "$token" | xargs)
            if [ -n "$token" ]; then
                echo "Unregistering runner with token: ${token:0:10}..."
                ./config.sh remove --token "$token" 2>/dev/null || true
            fi
        done
        cd "$RUNNER_DATA_DIR"
    fi

    # Then, use GitHub API to remove runners by name (more reliable)
    # This works without local config files
    if [ -n "$UNREGISTER_RUNNERS" ]; then
        echo "Removing runners by name via GitHub API..."
        IFS=',' read -ra UNREGISTER_REPO_ARRAY <<< "$UNREGISTER_RUNNERS"
        for repo_item in "${UNREGISTER_REPO_ARRAY[@]}"; do
            repo_item=$(echo "$repo_item" | xargs)
            if [ -z "$repo_item" ]; then
                continue
            fi
            # Extract owner/repo from URL or use as-is
            REPO_PATH=$(echo "$repo_item" | sed 's|https://github.com/||; s|\.git$||')
            echo "Checking runners for $REPO_PATH..."

            # List runners for this repo
            RUNNERS_JSON=$(gh api -H "Accept: application/vnd.github+json" \
                "/repos/$REPO_PATH/actions/runners" 2>/dev/null)

            if [ -z "$RUNNERS_JSON" ] || [ "$RUNNERS_JSON" = "null" ]; then
                echo "  No runners found or API error for $REPO_PATH"
                continue
            fi

            # Find runners matching our prefix
            RUNNER_IDS=$(echo "$RUNNERS_JSON" | jq -r ".runners[] | select(.name | startswith(\"$RUNNER_NAME_PREFIX-\")) | .id")

            if [ -z "$RUNNER_IDS" ]; then
                echo "  No runners with prefix '$RUNNER_NAME_PREFIX-' found for $REPO_PATH"
                continue
            fi

            for runner_id in $RUNNER_IDS; do
                echo "  Removing runner ID $runner_id from $REPO_PATH..."
                gh api --method DELETE -H "Accept: application/vnd.github+json" \
                    "/repos/$REPO_PATH/actions/runners/$runner_id" 2>/dev/null && \
                    echo "  Runner $runner_id removed successfully" || \
                    echo "  Failed to remove runner $runner_id"
            done
        done
    fi

    echo "Unregistration complete."
fi

# Split GITHUB_URL by comma into array
IFS=',' read -ra GITHUB_URLS_RAW <<< "$GITHUB_URL"

# Process URLs: expand abbreviated ones (starting with /) using base from first full URL
GITHUB_URLS=()
BASE_URL=""
for url in "${GITHUB_URLS_RAW[@]}"; do
    url=$(echo "$url" | xargs)  # trim whitespace
    if [ -z "$url" ]; then
        continue
    fi
    if [[ "$url" =~ ^/ ]]; then
        # Abbreviated URL like /repo2 - prepend base URL
        if [ -z "$BASE_URL" ]; then
            echo "Error: Abbreviated URL '$url' used but no base URL found (first URL must be full)"
            exit 1
        fi
        GITHUB_URLS+=("${BASE_URL}${url}")
    else
        # Full URL - extract base for potential abbreviated URLs later
        # Base is everything up to and including the owner (e.g., https://github.com/owner)
        if [[ "$url" =~ ^(https://github\.com/[^/]+/[^/]+) ]]; then
            # We need the base up to the owner, not including the repo
            BASE_URL=$(echo "$url" | sed -E 's|^(https://github\.com/[^/]+)/.*$|\1|')
        fi
        GITHUB_URLS+=("$url")
    fi
done

if [ ${#GITHUB_URLS[@]} -eq 0 ]; then
    echo "Error: No valid repository URLs found in GITHUB_URL"
    exit 1
fi

echo "Resolved repository URLs:"
for u in "${GITHUB_URLS[@]}"; do
    echo "  $u"
done

# Authenticate with gh once using GH_PAT
echo "Authenticating with GitHub CLI using GH_PAT..."
# Set GH_TOKEN env var for gh CLI (works better than stored credentials in containers)
export GH_TOKEN="$GH_PAT"
# Verify authentication worked
echo "Verifying GitHub authentication..."
gh auth status
# Test API access with a simple call
echo "Testing GitHub API access..."
gh api "/user" --jq '.login' || echo "API test failed, but continuing..."

# Array to store runner PIDs
RUNNER_PIDS=()
RUNNER_DIRS=()
FAILED_REPOS=()

# Cleanup function to stop all runners on exit
cleanup() {
    echo "Shutting down runners..."
    for pid in "${RUNNER_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    # Wait for all runners to stop
    for pid in "${RUNNER_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    echo "All runners stopped."
    exit 0
}

# Trap signals for graceful shutdown
trap cleanup SIGTERM SIGINT

# Process each repository URL sequentially
for GITHUB_URL_ITEM in "${GITHUB_URLS[@]}"; do
    echo "=========================================="
    echo "Processing repository: $GITHUB_URL_ITEM"
    echo "=========================================="

    # Extract owner/repo from URL (e.g. https://github.com/owner/repo)
    # Remove .git suffix if present
    REPO_PATH=$(echo "$GITHUB_URL_ITEM" | sed 's|https://github.com/||; s|\.git$||')

    # Extract repo name (last part after /)
    REPO_NAME=$(echo "$REPO_PATH" | awk -F'/' '{print $NF}')

    # Construct runner name from prefix + repo name
    RUNNER_NAME="${RUNNER_NAME_PREFIX}-${REPO_NAME}"

    # Create isolated runner directory under persistent data directory
    RUNNER_DIR="${RUNNER_DATA_DIR}/runner-${REPO_NAME}"
    RUNNER_WORKDIR="${RUNNER_DATA_DIR}/${RUNNER_WORKDIR_BASE}/${REPO_NAME}"

    echo "Runner Name: $RUNNER_NAME"
    echo "Runner Directory: $RUNNER_DIR"
    echo "Work Directory: $RUNNER_WORKDIR"

    # Create runner directory
    mkdir -p "$RUNNER_DIR"

    # Symlink runner binaries into runner directory so config.sh and run.sh are available
    # We need: config.sh, run.sh, bin/, externals/ (if exists)
    ln -sf "$RUNNER_BASE_DIR/config.sh" "$RUNNER_DIR/config.sh"
    ln -sf "$RUNNER_BASE_DIR/run.sh" "$RUNNER_DIR/run.sh"
    ln -sf "$RUNNER_BASE_DIR/bin" "$RUNNER_DIR/bin"
    if [ -d "$RUNNER_BASE_DIR/externals" ]; then
        ln -sf "$RUNNER_BASE_DIR/externals" "$RUNNER_DIR/externals"
    fi

    cd "$RUNNER_DIR"

    # Cleanup previous configuration if it exists
    if [ -f .runner ]; then
        echo "Removing previous Runner configuration..."
        ./config.sh remove --token "$GITHUB_TOKEN" 2>/dev/null || true
    fi

    echo "Cleaning up old runner files and credentials..."
    rm -rf .runner .credentials* 2>/dev/null || true

    # Generate registration token for this repository
    echo "Generating Registration Token for $REPO_PATH..."
    # Capture both stdout and stderr to handle errors properly
    # Use timeout to prevent hanging (10 seconds)
    GH_API_OUTPUT=$(timeout 10 gh api --method POST -H "Accept: application/vnd.github+json" "/repos/$REPO_PATH/actions/runners/registration-token" 2>&1)
    GH_API_EXIT_CODE=$?
    if [ $GH_API_EXIT_CODE -eq 124 ]; then
        echo "Error: Timeout generating registration token for $REPO_PATH (30s)"
        FAILED_REPOS+=("$REPO_PATH")
        if [ "$FAIL_FAST" = "true" ]; then
            exit 1
        else
            echo "WARNING: Skipping $REPO_PATH due to timeout (FAIL_FAST=false)"
            cd "$RUNNER_DATA_DIR"
            continue
        fi
    fi

    if [ $GH_API_EXIT_CODE -ne 0 ]; then
        echo "Error: Failed to generate registration token for $REPO_PATH"
        echo "GitHub API response: $GH_API_OUTPUT"
        FAILED_REPOS+=("$REPO_PATH")
        if [ "$FAIL_FAST" = "true" ]; then
            exit 1
        else
            echo "WARNING: Skipping $REPO_PATH due to error (FAIL_FAST=false)"
            cd "$RUNNER_DATA_DIR"
            continue
        fi
    fi

    GITHUB_TOKEN=$(echo "$GH_API_OUTPUT" | jq -r .token | sed 's/\"//g' 2>/dev/null)

    if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "null" ]; then
        echo "Error: Failed to parse registration token for $REPO_PATH"
        echo "GitHub API response: $GH_API_OUTPUT"
        FAILED_REPOS+=("$REPO_PATH")
        if [ "$FAIL_FAST" = "true" ]; then
            exit 1
        else
            echo "WARNING: Skipping $REPO_PATH due to error (FAIL_FAST=false)"
            cd "$RUNNER_DATA_DIR"
            continue
        fi
    fi
    echo "Registration Token generated successfully."

    # Configure the runner
    echo "Configuring GitHub Runner for $REPO_PATH..."
    ./config.sh --url "$GITHUB_URL_ITEM" --token "$GITHUB_TOKEN" --name "$RUNNER_NAME" --work "$RUNNER_WORKDIR" --labels "$RUNNER_LABELS" --unattended--replace

    echo "Configuration done for $RUNNER_NAME."

    # Start the runner in background
    echo "Starting Runner $RUNNER_NAME..."
    ./run.sh &
    RUNNER_PID=$!
    RUNNER_PIDS+=("$RUNNER_PID")
    RUNNER_DIRS+=("$RUNNER_DIR")

    echo "Runner $RUNNER_NAME started with PID $RUNNER_PID"

    # Go back to data directory for next iteration
    cd "$RUNNER_DATA_DIR"
done

if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
    echo "=========================================="
    echo "WARNING: The following repositories failed:"
    for repo in "${FAILED_REPOS[@]}"; do
        echo "  $repo"
    done
    echo "=========================================="
fi

if [ ${#RUNNER_PIDS[@]} -eq 0 ]; then
    echo "Error: No runners started successfully."
    exit 1
fi

echo "=========================================="
echo "All ${#RUNNER_PIDS[@]} runners started successfully."
echo "Runner PIDs: ${RUNNER_PIDS[*]}"
echo "=========================================="

# Wait for all runner processes
wait
