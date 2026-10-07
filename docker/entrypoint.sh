#!/bin/bash
set -e

# Validate environment variables
if [ -z "$GITHUB_URL" ]; then
    echo "Error: GITHUB_URL is not set"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    if [ -n "$GH_PAT" ] && [ -n "$GITHUB_URL" ]; then
        echo "Generating Registration Token using GH_PAT..."
        # Extract owner and repo from URL (e.g. https://github.com/owner/repo)
        # Remove .git suffix if present (single sed call)
        REPO_PATH=$(echo "$GITHUB_URL" | sed 's|https://github.com/||; s|\.git$||')

        # Authenticate with gh
        echo "$GH_PAT" | gh auth login --with-token

        # Fetch token
        GITHUB_TOKEN=$(gh api --method POST -H "Accept: application/vnd.github+json" \
            "/repos/$REPO_PATH/actions/runners/registration-token" | jq -r .token)

        if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "null" ]; then
            echo "Error: Failed to generate registration token via API."
            exit 1
        fi
        echo "Registration Token generated successfully."
    else
        echo "Error: GITHUB_TOKEN is not set (and no GH_PAT provided)"
        exit 1
    fi
fi

# Set defaults
RUNNER_NAME=${RUNNER_NAME:-$(hostname)}
RUNNER_WORKDIR=${RUNNER_WORKDIR:-_work}
LABELS=${RUNNER_LABELS:-default}

# Start SSH daemon
echo "Starting SSH Daemon..."
sudo /usr/sbin/sshd

echo "Configuring GitHub Runner..."
echo "URL: $GITHUB_URL"
echo "Runner Name: $RUNNER_NAME"

# Cleanup previous configuration if it exists
if [ -f .runner ]; then
    echo "Removing previous Runner configuration..."
    ./config.sh remove --token "$GITHUB_TOKEN" || true
fi

# Configure the runner
./config.sh \
    --url "$GITHUB_URL" \
    --token "$GITHUB_TOKEN" \
    --name "$RUNNER_NAME" \
    --work "$RUNNER_WORKDIR" \
    --labels "$LABELS" \
    --unattended \
    --replace

echo "Starting configuration done."

# Run the runner
echo "Starting Runner..."
exec ./run.sh
