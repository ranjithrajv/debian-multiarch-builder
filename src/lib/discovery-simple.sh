#!/bin/bash

# Simplified discovery module

# Source utilities
source "$SCRIPT_DIR/data/yaml-utils.sh"

# Auto-discover pattern for architecture
auto_discover_pattern() {
    local arch=$1
    local pattern=$(yq eval ".architecture_patterns.${arch}" "$SCRIPT_DIR/data/architecture-patterns.yaml")
    
    if [ "$pattern" = "null" ] || [ -z "$pattern" ]; then
        return 1
    fi
    
    # Get release assets using centralized API function
    local assets=$(fetch_release_assets)
    
    if [ -z "$assets" ]; then
        return 1
    fi
    
    # Filter assets by pattern
    local filtered_assets=$(echo "$assets" | \
        grep -E "\.(${ARTIFACT_FORMAT:-tar.gz}|tgz|tar\.gz|zip)$" | \
        grep -v -i "sha256\|checksum\|source" | \
        grep -iE "$pattern" | \
        grep -i "linux" || true)
    
    if [ -z "$filtered_assets" ]; then
        return 1
    fi
    
    # Get first match
    local matched_asset=$(echo "$filtered_assets" | head -1)
    if [ -z "$matched_asset" ]; then
        return 1
    fi
    
    echo "$matched_asset"
    return 0
}

# Get release pattern for architecture
get_release_pattern() {
    local arch=$1
    
    if [ "$AUTO_DISCOVERY" = "true" ]; then
        # Auto-discovery mode - return placeholder for now
        echo "{arch}_${version}.${ARTIFACT_FORMAT:-tar.gz}"
        return 0
    else
        # Manual mode
        local pattern=$(yq eval ".architectures.${arch}.release_pattern" "$CONFIG_FILE")
        
        if [ "$pattern" = "null" ] || [ -z "$pattern" ]; then
            return 1
        fi
        
        # Replace {version} placeholder (use variable to avoid } closing outer ${...})
        local _ver='{version}'
        pattern="${pattern//$_ver/$VERSION}"
        echo "$pattern"
        return 0
    fi
}

# Detect artifact format from filename
detect_artifact_format() {
    local filename=$1
    
    if [[ "$filename" =~ \.zip$ ]]; then
        echo "zip"
        return 0
    elif [[ "$filename" =~ \.tar\.gz$ ]]; then
        echo "tar.gz"
        return 0
    elif [[ "$filename" =~ \.tgz$ ]]; then
        echo "tgz"
        return 0
    else
        echo "tar.gz"
        return 1
    fi
}

# Fetch release assets - use centralized function
fetch_release_assets() {
    # Source the github-api library to use the centralized function
    source "$SCRIPT_DIR/lib/github-api.sh"
    fetch_release_assets "$@"
}