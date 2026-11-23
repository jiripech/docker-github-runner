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

# Start SSH daemon
echo "Starting SSH Daemon..."
sudo /usr/sbin/sshd

# Split GITHUB_URL by comma into array
IFS=',' read -ra GITHUB_URLS <<< "$GITHUB_URL"

# Authenticate with gh once using GH_PAT
echo "Authenticating with GitHub CLI using GH_PAT..."
echo "$GH_PAT" | gh auth login --with-token

# Array to store runner PIDs
RUNNER_PIDS=()
RUNNER_DIRS=()

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
    # Trim whitespace
    GITHUB_URL_ITEM=$(echo "$GITHUB_URL_ITEM" | xargs)

    if [ -z "$GITHUB_URL_ITEM" ]; then
        continue
    fi

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

    # Create isolated runner directory
    RUNNER_DIR="runner-${REPO_NAME}"
    RUNNER_WORKDIR="${RUNNER_WORKDIR_BASE}/${REPO_NAME}"

    echo "Runner Name: $RUNNER_NAME"
    echo "Runner Directory: $RUNNER_DIR"
    echo "Work Directory: $RUNNER_WORKDIR"

    # Create runner directory
    mkdir -p "$RUNNER_DIR"
    cd "$RUNNER_DIR"

    # Cleanup previous configuration if it exists
    if [ -f .runner ]; then
        echo "Removing previous Runner configuration..."
        ./config.sh remove --token "$GITHUB_TOKEN" 2>/dev/null || true
    fi

    # Generate registration token for this repository
    echo "Generating Registration Token for $REPO_PATH..."
    GITHUB_TOKEN=$(gh api --method POST -H "Accept: application/vnd.github+json" \
        "/repos/$REPO_PATH/actions/runners/registration-token" | jq -r .token)

    if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "null" ]; then
        echo "Error: Failed to generate registration token for $REPO_PATH"
        exit 1
    fi
    echo "Registration Token generated successfully."

    # Configure the runner
    echo "Configuring GitHub Runner for $REPO_PATH..."
    ./config.sh \
        --url "$GITHUB_URL_ITEM" \
        --token "$GITHUB_TOKEN" \
        --name "$RUNNER_NAME" \
        --work "$RUNNER_WORKDIR" \
        --labels "$RUNNER_LABELS" \
        --unattended \
        --replace

    echo "Configuration done for $RUNNER_NAME."

    # Start the runner in background
    echo "Starting Runner $RUNNER_NAME..."
    ./run.sh &
    RUNNER_PID=$!
    RUNNER_PIDS+=("$RUNNER_PID")
    RUNNER_DIRS+=("$RUNNER_DIR")

    echo "Runner $RUNNER_NAME started with PID $RUNNER_PID"

    # Go back to base directory for next iteration
    cd ..
done

echo "=========================================="
echo "All ${#RUNNER_PIDS[@]} runners started successfully."
echo "Runner PIDs: ${RUNNER_PIDS[*]}"
echo "=========================================="

# Wait for all runner processes
wait