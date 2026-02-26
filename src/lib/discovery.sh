#!/bin/bash

# Architecture pattern discovery functions

# Source YAML utilities for loading externalized configuration
source "$SCRIPT_DIR/data/yaml-utils.sh"

# Load architecture patterns data
load_architecture_patterns

# Function to auto-detect artifact format from release pattern
detect_artifact_format() {
    local release_pattern=$1
    
    # Extract the file extension from the release pattern
    if [[ "$release_pattern" =~ \.zip$ ]]; then
        echo "zip"
        return 0
    elif [[ "$release_pattern" =~ \.tar\.gz$ ]]; then
        echo "tar.gz"
        return 0
    elif [[ "$release_pattern" =~ \.tgz$ ]]; then
        echo "tgz"
        return 0
    else
        # If no recognized extension found, return default
        echo "tar.gz"
        return 1
    fi
}

# Function to auto-discover release pattern for an architecture
auto_discover_pattern() {
    local arch=$1
    local pattern=$(get_architecture_pattern "$arch")

    if [ -z "$pattern" ] || [ "$pattern" = "null" ]; then
        return 1
    fi

    # Fetch all release assets
    local assets=$(fetch_release_assets)

    # Filter assets by format and pattern, filter out checksums and source
    # Use default format for initial filtering
    local filtered_assets=$(echo "$assets" | \
        grep -E "\\.(${ARTIFACT_FORMAT:-tar.gz}|tgz|tar\\.gz|zip)$" | \
        grep -v -i "sha256\|checksum\|source" | \
        grep -iE "$pattern" | \
        grep -i "linux")

    # Prefer builds based on auto-discovery preferences
    for build_type in $(get_auto_discovery_preferences); do
        local matched_asset=$(echo "$filtered_assets" | grep -i "$build_type" | head -1)
        if [ -n "$matched_asset" ]; then
            echo "$matched_asset"
            return 0
        fi
    done

    # Fallback to first match if no preferred build type found
    local matched_asset=$(echo "$filtered_assets" | head -1)
    if [ -z "$matched_asset" ]; then
        return 1
    fi

    echo "$matched_asset"
    return 0
}

# Function to get release pattern for an architecture
get_release_pattern() {
    local arch=$1

    if [ "$AUTO_DISCOVERY" = "true" ]; then
        # Auto-discovery mode
        local pattern=$(auto_discover_pattern "$arch")
        if [ $? -ne 0 ] || [ -z "$pattern" ]; then
            return 1
        fi
        echo "$pattern"
        return 0
    else
        # Manual mode
        local pattern=$(yq eval ".architectures.${arch}.release_pattern" "$CONFIG_FILE")

        if [ "$pattern" = "null" ] || [ -z "$pattern" ]; then
            return 1
        fi

        # Replace {version} placeholder with actual version
        # Use a local variable to hold the search string so that the `}` in
        # {version} does not prematurely close the outer ${...} expansion.
        local _ver='{version}'
        pattern="${pattern//$_ver/$VERSION}"
        echo "$pattern"
        return 0
    fi
}