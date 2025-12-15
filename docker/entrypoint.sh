#!/bin/bash
set -e

# Validate environment variables
if [ -z "$GITHUB_URL" ]; then
    echo "Error: GITHUB_URL is not set"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN is not set"
    exit 1
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
