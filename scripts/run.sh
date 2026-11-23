#!/bin/bash
set -e

# Usage: ./scripts/run.sh <GITHUB_URL> <GH_PAT> <RUNNER_NAME_PREFIX> [RUNNER_LABELS] [IMAGE_NAME]
# For single runner (legacy): ./scripts/run.sh <GITHUB_URL> <GITHUB_TOKEN> [RUNNER_NAME]

GITHUB_URL=$1
GH_PAT=$2
RUNNER_NAME_PREFIX=$3
RUNNER_LABELS=${4:-"default"}
IMAGE_NAME=${5:-"test-runner-complete"}

if [ -z "$GITHUB_URL" ] || [ -z "$GH_PAT" ] || [ -z "$RUNNER_NAME_PREFIX" ]; then
    echo "Usage: $0 <GITHUB_URL> <GH_PAT> <RUNNER_NAME_PREFIX> [RUNNER_LABELS] [IMAGE_NAME]"
    echo ""
    echo "Examples:"
    echo "  Single runner (legacy):"
    echo "    $0 https://github.com/owner/repo ghp_token my-runner"
    echo ""
    echo "  Multi-runner:"
    echo "    $0 \"https://github.com/owner/repo1,https://github.com/owner/repo2\" ghp_token ci-runner \"gpu,linux\""
    exit 1
fi

# Create local directories for volumes if they don't exist
# We use .runner to keep it hidden and ignored by git (see .gitignore)
mkdir -p ./.runner/logs
mkdir -p ./.runner/work

# Determine container name from prefix (first repo)
FIRST_REPO=$(echo "$GITHUB_URL" | cut -d',' -f1 | xargs)
REPO_NAME=$(echo "$FIRST_REPO" | sed 's|https://github.com/||; s|\.git$||' | awk -F'/' '{print $NF}')
CONTAINER_NAME="${RUNNER_NAME_PREFIX}-${REPO_NAME}"

echo "Starting runner(s) with prefix '$RUNNER_NAME_PREFIX' for '$GITHUB_URL'..."
echo "Container name: $CONTAINER_NAME"
echo "Labels: $RUNNER_LABELS"
echo "Logs will be in $(pwd)/.runner/logs"
echo "Workdir will be in $(pwd)/.runner/work"

docker run -d \
    --restart unless-stopped \
    --name "$CONTAINER_NAME" \
    -e GITHUB_URL="$GITHUB_URL" \
    -e GH_PAT="$GH_PAT" \
    -e RUNNER_NAME_PREFIX="$RUNNER_NAME_PREFIX" \
    -e RUNNER_LABELS="$RUNNER_LABELS" \
    -v "$(pwd)/.runner/logs:/home/runner/_diag" \
    -v "$(pwd)/.runner/work:/home/runner/_work" \
    -p 2222:22 \
    "$IMAGE_NAME"

echo "Container '$CONTAINER_NAME' started."
echo "SSH Access: ssh -p 2222 runner@localhost"
