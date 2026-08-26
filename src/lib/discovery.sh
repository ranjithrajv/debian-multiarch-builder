#!/bin/bash

# Auto-discovery of release assets and architecture patterns

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
    
    # Filter assets by pattern. "raw" (a bare, unarchived binary - some
    # goreleaser/cargo-dist configs skip archiving a single-binary release,
    # e.g. jandedobbeleer/oh-my-posh's "posh-linux-amd64") has no extension
    # to match, so exclude known non-binary asset types instead of requiring
    # one.
    local filtered_assets
    if [ "$ARTIFACT_FORMAT" = "raw" ]; then
        filtered_assets=$(echo "$assets" | \
            grep -viE '\.(tar\.gz|tgz|tar\.xz|tar\.bz2|tar\.zst|zip|deb|rpm|exe|dmg|pkg|txt|md|json|sig|asc|sha256|sha256sum|sha512|sbom)$' | \
            grep -v -i "sha256\|checksum\|source" | \
            grep -iE "$pattern" | \
            grep -i "linux" || true)
    else
        filtered_assets=$(echo "$assets" | \
            grep -E "\.(${ARTIFACT_FORMAT:-tar.gz}|tgz|tar\.gz|tar\.xz|tar\.bz2|tar\.zst|zip)$" | \
            grep -v -i "sha256\|checksum\|source" | \
            grep -iE "$pattern" | \
            grep -i "linux" || true)
    fi

    if [ -z "$filtered_assets" ]; then
        return 1
    fi

    # Prefer builds by auto_discovery_preferences (gnu > musl > linux) before
    # falling back to the first match, so e.g. a gnu build is picked over an
    # equally-matching musl one when both are available for an architecture.
    local build_type
    for build_type in $(get_auto_discovery_preferences); do
        local preferred_match=$(echo "$filtered_assets" | grep -i "$build_type" | head -1)
        if [ -n "$preferred_match" ]; then
            echo "$preferred_match"
            return 0
        fi
    done

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
        auto_discover_pattern "$arch"
        return $?
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
    elif [[ "$filename" =~ \.tar\.xz$ ]]; then
        echo "tar.xz"
        return 0
    elif [[ "$filename" =~ \.tar\.bz2$ ]]; then
        echo "tar.bz2"
        return 0
    elif [[ "$filename" =~ \.tar\.zst$ ]]; then
        echo "tar.zst"
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