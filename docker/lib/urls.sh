#!/bin/bash
# urls.sh - Parse and normalize GITHUB_URL into array

parse_github_urls() {
    # Split GITHUB_URL by comma into array
    IFS=',' read -ra GITHUB_URLS_RAW <<< "$GITHUB_URL"

    # Process URLs: expand abbreviated ones (starting with /) using base from first full URL
    GITHUB_URLS=()
    BASE_URL=""
    for url in "${GITHUB_URLS_RAW[@]}"; do
        url=$(echo "$url" | xargs)  # trim whitespace
        if [ -z "$url" ]; then
            continue
        fi
        if [[ "$url" =~ ^/ ]]; then
            # Abbreviated URL like /repo2 - prepend base URL
            if [ -z "$BASE_URL" ]; then
                echo "Error: Abbreviated URL '$url' used but no base URL found (first URL must be full)"
                exit 1
            fi
            GITHUB_URLS+=("${BASE_URL}${url}")
        else
            # Full URL - extract base for potential abbreviated URLs later
            # Base is everything up to and including the owner (e.g., https://github.com/owner)
            if [[ "$url" =~ ^(https://github\.com/[^/]+/[^/]+) ]]; then
                # We need the base up to the owner, not including the repo
                BASE_URL=$(echo "$url" | sed -E 's|^(https://github\.com/[^/]+)/.*$|\1|')
            fi
            GITHUB_URLS+=("$url")
        fi
    done

    if [ ${#GITHUB_URLS[@]} -eq 0 ]; then
        echo "Error: No valid repository URLs found in GITHUB_URL"
        exit 1
    fi

    echo "Resolved repository URLs:"
    for u in "${GITHUB_URLS[@]}"; do
        echo "  $u"
    done

    # Set GH_TOKEN env var for gh CLI (works better than stored credentials in containers)
    export GH_TOKEN="$GH_PAT"
}