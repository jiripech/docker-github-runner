#!/bin/bash
set -e

# Usage: ./scripts/run.sh <GITHUB_URL> <GITHUB_TOKEN> [RUNNER_NAME]

GITHUB_URL=$1
GITHUB_TOKEN=$2
RUNNER_NAME=${3:-"my-runner-$(hostname)"}
IMAGE_NAME="test-runner-complete" # Or whatever image name you built

if [ -z "$GITHUB_URL" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "Usage: $0 <GITHUB_URL> <GITHUB_TOKEN> [RUNNER_NAME]"
    exit 1
fi

# Create local directories for volumes if they don't exist
mkdir -p ./data/logs
mkdir -p ./data/work

echo "Starting runner '$RUNNER_NAME' for '$GITHUB_URL'..."
echo "Logs will be in $(pwd)/data/logs"
echo "Workdir will be in $(pwd)/data/work"

# Calculate local architecture for correct labels (optional, but good for run)
# But labels are usually handled by runner config default.
# We mapped port 2222 for SSH.

docker run -d \
    --restart unless-stopped \
    --name "$RUNNER_NAME" \
    -e GITHUB_URL="$GITHUB_URL" \
    -e GITHUB_TOKEN="$GITHUB_TOKEN" \
    -e RUNNER_NAME="$RUNNER_NAME" \
    -v "$(pwd)/data/logs:/home/runner/_diag" \
    -v "$(pwd)/data/work:/home/runner/_work" \
    -p 2222:22 \
    "$IMAGE_NAME"

echo "Container '$RUNNER_NAME' started."
echo "SSH Access: ssh -p 2222 runner@localhost"
