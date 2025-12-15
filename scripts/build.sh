#!/bin/bash
set -e

# Image name is required
if [ -z "$1" ]; then
    echo "Usage: $0 <image-name> [push|load]"
    exit 1
fi

IMAGE_NAME=$1
ACTION=${2:-push}

# Resolve script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_ASSETS="$REPO_ROOT/docker"

# Find SSH Public Key (Strongest First)
SSH_PUB_KEY_PATH=""
# Check if SSH public keys exist in order of algorithm security preference
for keyalgs in ed25519 ecdsa rsa dsa; do
    if [ -f "$HOME/.ssh/id_$keyalgs" ] && [ -f "$HOME/.ssh/id_$keyalgs.pub" ]; then
        SSH_PUB_KEY_PATH="$HOME/.ssh/id_$keyalgs.pub"
        echo "Found SSH key: $SSH_PUB_KEY_PATH"
        break;
    fi
done

if [ -z "$SSH_PUB_KEY_PATH" ]; then
    echo "Error: Could not find any SSH public key (ed25519, ecdsa, rsa, dsa) in ~/.ssh/"
    exit 1
fi

# Create a temporary directory for the build context
BUILD_CONTEXT=$(mktemp -d /tmp/docker-build-context.XXXXXX)
echo "Created temporary build context at $BUILD_CONTEXT"

# cleanup function
cleanup() {
    echo "Cleaning up temporary build context..."
    rm -rf "$BUILD_CONTEXT"
}
trap cleanup EXIT

# Prepare build context
echo "Copying assets to build context..."
# Copy all files from docker/ to root of build context
cp "$DOCKER_ASSETS/"* "$BUILD_CONTEXT/"

# Inject SSH Key
echo "Injecting SSH public key from $SSH_PUB_KEY_PATH..."
cat "$SSH_PUB_KEY_PATH" > "$BUILD_CONTEXT/authorized_keys"
# Ensure newline
echo "" >> "$BUILD_CONTEXT/authorized_keys"

# Build
# Ensure buildx builder exists
if ! docker buildx inspect gh-runner-builder > /dev/null 2>&1; then
    echo "Creating new buildx builder..."
    docker buildx create --name gh-runner-builder --use
    docker buildx inspect --bootstrap
else
    echo "Using existing buildx builder..."
    docker buildx use gh-runner-builder
fi

echo "Building $IMAGE_NAME for amd64 and arm64..."

if [ "$ACTION" = "load" ]; then
    # Load only current architecture for local testing
    echo "Loading local architecture..."
    LOCAL_ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
    docker buildx build --progress=plain --platform linux/$LOCAL_ARCH -t "$IMAGE_NAME" --load "$BUILD_CONTEXT"
else
    echo "Building and pushing..."
    docker buildx build --progress=plain --platform linux/amd64,linux/arm64 -t "$IMAGE_NAME" --push "$BUILD_CONTEXT"
fi
