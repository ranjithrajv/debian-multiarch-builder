#!/bin/bash

# Essential validation and utility functions

# Check for required tools
check_requirements() {
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
    fi
    
    if ! docker ps &> /dev/null; then
        error "Docker daemon is not running or you don't have permission to access it"
    fi
}

# Cleanup API cache
cleanup_api_cache() {
    local cache_file="/tmp/release_assets_${GITHUB_REPO//\//_}_${VERSION}.cache"
    rm -f "$cache_file" 2>/dev/null || true
}

# Cleanup lintian results
cleanup_lintian_results() {
    rm -rf .lintian-results 2>/dev/null || true
}