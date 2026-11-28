#!/bin/bash
# runner.sh - Per-repository runner setup and start

# Arrays to store runner info (declared in main, exported here)
# RUNNER_PIDS=()
# RUNNER_DIRS=()
# FAILED_REPOS=()

setup_and_start_runner() {
    local GITHUB_URL_ITEM="$1"

    echo "=========================================="
    echo "Processing repository: $GITHUB_URL_ITEM"
    echo "=========================================="

    # Extract owner/repo from URL (e.g. https://github.com/owner/repo)
    # Remove .git suffix if present
    local REPO_PATH
    REPO_PATH=$(echo "$GITHUB_URL_ITEM" | sed 's|https://github.com/||; s|\.git$||')

    # Extract repo name (last part after /)
    local REPO_NAME
    REPO_NAME=$(echo "$REPO_PATH" | awk -F'/' '{print $NF}')

    # Construct runner name from prefix + repo name
    local RUNNER_NAME="${RUNNER_NAME_PREFIX}-${REPO_NAME}"

    # Create isolated runner directory under persistent data directory
    local RUNNER_DIR="${RUNNER_DATA_DIR}/${REPO_NAME}"
    local RUNNER_WORKDIR="${RUNNER_DIR}/${RUNNER_WORKDIR_BASE}"

    echo "Runner Name: $RUNNER_NAME"
    echo "Runner Directory: $RUNNER_DIR"
    echo "Work Directory: $RUNNER_WORKDIR"

    # Create runner directory
    mkdir -p "$RUNNER_DIR"

    # Copy runner installation to runner directory (each runner needs its own isolated installation
    # because the runner binary determines its root from its own location, not from CWD)
    echo "Copying runner installation to $RUNNER_DIR..."
    rsync -a --delete "$RUNNER_BASE_DIR/" "$RUNNER_DIR/"

    cd "$RUNNER_DIR" || return 1

    # Cleanup previous configuration if it exists
    echo "Cleaning up old runner files and credentials..."
    rm -rf .runner .runner_migrated .credentials* .credentials_rsaparams* 2>/dev/null || true

    # Generate registration token for this repository
    echo "Generating Registration Token for $REPO_PATH..."
    # Use curl directly with GH_PAT as Bearer token for better error visibility
    # Save response and error to separate files for debugging
    local RESPONSE_FILE="registration_token_${REPO_NAME}.json"
    local ERROR_FILE="registration_token_${REPO_NAME}.err"

    echo "  Calling GitHub API: POST /repos/$REPO_PATH/actions/runners/registration-token"
    local HTTP_CODE
    HTTP_CODE=$(curl -sS -m 10 -w "%{http_code}" -o "$RESPONSE_FILE" -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GH_PAT" \
        "https://api.github.com/repos/$REPO_PATH/actions/runners/registration-token" 2>"$ERROR_FILE")
    local CURL_EXIT_CODE=$?

    # See curl errors on stdout if any
    [ -s "$ERROR_FILE" ] && echo "  curl stderr: $(cat "$ERROR_FILE")"

    if [ $CURL_EXIT_CODE -eq 28 ]; then
        echo "Error: Timeout generating registration token for $REPO_PATH (10s)"
        FAILED_REPOS+=("$REPO_PATH")
        if [ "$FAIL_FAST" = "true" ]; then
            exit 1
        else
            echo "WARNING: Skipping $REPO_PATH due to timeout (FAIL_FAST=false)"
            cd "$RUNNER_DATA_DIR" || return 1
            return
        fi
    fi

    if [ $CURL_EXIT_CODE -ne 0 ]; then
        echo "Error: curl failed with exit code $CURL_EXIT_CODE for $REPO_PATH"
        FAILED_REPOS+=("$REPO_PATH")
        if [ "$FAIL_FAST" = "true" ]; then
            exit 1
        else
            echo "WARNING: Skipping $REPO_PATH due to curl error (FAIL_FAST=false)"
            cd "$RUNNER_DATA_DIR" || return 1
            return
        fi
    fi

    echo "  HTTP response code: $HTTP_CODE"

    if [ "$HTTP_CODE" -ne 201 ] && [ "$HTTP_CODE" -ne 200 ]; then
        echo "Error: GitHub API returned HTTP $HTTP_CODE for $REPO_PATH"
        echo "  Response: $(cat "$RESPONSE_FILE")"
        FAILED_REPOS+=("$REPO_PATH")
        if [ "$FAIL_FAST" = "true" ]; then
            exit 1
        else
            echo "WARNING: Skipping $REPO_PATH due to API error (FAIL_FAST=false)"
            cd "$RUNNER_DATA_DIR" || return 1
            return
        fi
    fi

    local GITHUB_TOKEN
    GITHUB_TOKEN=$(jq -r .token "$RESPONSE_FILE" 2>/dev/null | sed 's/\"//g')

    if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "null" ]; then
        echo "Error: Failed to parse registration token for $REPO_PATH"
        echo "  Response: $(cat "$RESPONSE_FILE")"
        FAILED_REPOS+=("$REPO_PATH")
        if [ "$FAIL_FAST" = "true" ]; then
            exit 1
        else
            echo "WARNING: Skipping $REPO_PATH due to parse error (FAIL_FAST=false)"
            cd "$RUNNER_DATA_DIR" || return 1
            return
        fi
    fi
    echo "Registration Token generated successfully."

    # Clean up temp files
    rm -f "$RESPONSE_FILE" "$ERROR_FILE"

    # Configure the runner
    echo "Configuring GitHub Runner for $REPO_PATH..."
    ./config.sh --url "$GITHUB_URL_ITEM" --token "$GITHUB_TOKEN" --name "$RUNNER_NAME" --work "$RUNNER_WORKDIR" --labels "$RUNNER_LABELS" --unattended --replace

    echo "Configuration done for $RUNNER_NAME."

    # Start the runner in background
    echo "Starting Runner $RUNNER_NAME..."
    ./run.sh &
    local RUNNER_PID=$!
    RUNNER_PIDS+=("$RUNNER_PID")
    RUNNER_DIRS+=("$RUNNER_DIR")

    echo "Runner $RUNNER_NAME started with PID $RUNNER_PID"

    # Go back to data directory for next iteration
    cd "$RUNNER_DATA_DIR" || return 1
}