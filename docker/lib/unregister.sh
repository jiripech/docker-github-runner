#!/bin/bash
# unregister.sh - Handle UNREGISTER_TOKENS and UNREGISTER_RUNNERS

handle_unregister() {
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
            cd "$RUNNER_BASE_DIR" || exit 1
            for token in "${UNREGISTER_TOKEN_ARRAY[@]}"; do
                token=$(echo "$token" | xargs)
                if [ -n "$token" ]; then
                    echo "Unregistering runner with token: ${token:0:10}..."
                    ./config.sh remove --token "$token" 2>/dev/null || true
                fi
            done
            cd "$RUNNER_DATA_DIR" || exit 1
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
}