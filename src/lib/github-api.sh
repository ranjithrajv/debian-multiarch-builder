#!/bin/bash

# GitHub API interaction functions

# Cache for GitHub API release assets
RELEASE_ASSETS_CACHE=""

# Function to fetch release assets from GitHub API
fetch_release_assets() {
    # Return cached result if available
    if [ -n "$RELEASE_ASSETS_CACHE" ]; then
        echo "$RELEASE_ASSETS_CACHE"
        return 0
    fi

    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${VERSION}"
    info "Fetching release assets from GitHub API..."

    local assets=$(curl -sL "$api_url" | jq -r '.assets[]? | .name' 2>/dev/null)

    if [ -z "$assets" ]; then
        error "Failed to fetch release assets from $api_url

Possible reasons:
  - Version '$VERSION' doesn't exist for $GITHUB_REPO
  - GitHub API rate limit exceeded
  - Network connectivity issues

Please check: https://github.com/${GITHUB_REPO}/releases/tag/${VERSION}"
    fi

    # Cache the result
    RELEASE_ASSETS_CACHE="$assets"
    echo "$assets"
}
