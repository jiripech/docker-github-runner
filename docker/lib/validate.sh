#!/bin/bash
# validate.sh - Environment validation and defaults

validate_env() {
    # Validate required environment variables
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

    # Base runner installation directory (read-only from image)
    RUNNER_BASE_DIR="/home/runner"
    # Persistent data directory for runner configurations (mounted volume)
    RUNNER_DATA_DIR="/data"

    export RUNNER_LABELS RUNNER_WORKDIR_BASE FAIL_FAST RUNNER_BASE_DIR RUNNER_DATA_DIR
}