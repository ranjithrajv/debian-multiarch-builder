#!/bin/bash

# Architecture pattern discovery functions

# Architecture pattern mappings for auto-discovery
# Maps Debian arch to common upstream naming patterns
declare -A ARCH_PATTERNS=(
    ["amd64"]="x86_64|amd64|x64"
    ["arm64"]="aarch64|arm64"
    ["armel"]="arm-|armeabi"
    ["armhf"]="armv7|armhf|arm-.*gnueabihf"
    ["i386"]="i686|i386|x86"
    ["ppc64el"]="powerpc64le|ppc64le"
    ["s390x"]="s390x"
    ["riscv64"]="riscv64gc|riscv64"
)

# Function to auto-discover release pattern for an architecture
auto_discover_pattern() {
    local arch=$1
    local pattern="${ARCH_PATTERNS[$arch]}"

    if [ -z "$pattern" ]; then
        return 1
    fi

    # Fetch all release assets
    local assets=$(fetch_release_assets)

    # Filter assets by format and pattern, filter out checksums and source
    local filtered_assets=$(echo "$assets" | \
        grep -E "\.(${ARTIFACT_FORMAT}|tgz|tar\.gz|zip)$" | \
        grep -v -i "sha256\|checksum\|source" | \
        grep -iE "$pattern" | \
        grep -i "linux")

    # Prefer gnu builds (better for Debian), then musl builds, then any linux build
    local matched_asset=$(echo "$filtered_assets" | grep -i "gnu" | head -1)
    if [ -z "$matched_asset" ]; then
        matched_asset=$(echo "$filtered_assets" | grep -i "musl" | head -1)
    fi
    if [ -z "$matched_asset" ]; then
        matched_asset=$(echo "$filtered_assets" | head -1)
    fi

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

        # Validate pattern has {version} placeholder
        if [[ ! "$pattern" =~ \{version\} ]]; then
            warning "Release pattern for $arch doesn't contain {version} placeholder: $pattern"
        fi

        # Replace {version} placeholder with actual version
        pattern="${pattern//\{version\}/$VERSION}"
        echo "$pattern"
        return 0
    fi
}
