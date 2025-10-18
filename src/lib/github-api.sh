#!/bin/bash

# GitHub API interaction functions

# Function to fetch release assets from GitHub API
# Uses file-based cache to share data across parallel builds
fetch_release_assets() {
    # Generate cache file path (replace / with _ in repo name)
    local cache_file="/tmp/release_assets_${GITHUB_REPO//\//_}_${VERSION}.cache"

    # Check if cached file exists and return its contents
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
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

    # Write to cache file atomically (tmp file + move)
    echo "$assets" > "${cache_file}.tmp" && mv "${cache_file}.tmp" "$cache_file"
    echo "$assets"
}

# Function to cleanup API cache files
cleanup_api_cache() {
    local cache_file="/tmp/release_assets_${GITHUB_REPO//\//_}_${VERSION}.cache"
    if [ -f "$cache_file" ]; then
        rm -f "$cache_file" 2>/dev/null || true
    fi
}
