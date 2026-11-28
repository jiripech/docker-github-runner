#!/bin/bash
set -e

# Main entrypoint for GitHub Actions Runner container
# Sources modular scripts from /lib/ (copied in Dockerfile)

LIB_DIR="/lib"

# Source all modules
source "${LIB_DIR}/validate.sh"
source "${LIB_DIR}/ssh.sh"
source "${LIB_DIR}/unregister.sh"
source "${LIB_DIR}/urls.sh"
source "${LIB_DIR}/runner.sh"
source "${LIB_DIR}/wait.sh"

# Global arrays (populated by runner.sh)
RUNNER_PIDS=()
RUNNER_DIRS=()
FAILED_REPOS=()

# Main flow
validate_env
start_ssh
handle_unregister
parse_github_urls

# Process each repository URL sequentially
for GITHUB_URL_ITEM in "${GITHUB_URLS[@]}"; do
    setup_and_start_runner "$GITHUB_URL_ITEM"
done

# Wait for all runners and capture exit codes
wait_for_runners