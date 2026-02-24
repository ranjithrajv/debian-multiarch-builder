#!/bin/bash

# Simplified configuration module - essential functionality only

# Source data files and utilities  
source "$SCRIPT_DIR/data/yaml-utils.sh"
# distributions.yaml is a data file, not sourceable

# Parse and validate configuration file
parse_config() {
    local package_file="$1"
    local config_dir=$(dirname "$package_file")

    # Validate file exists
    if [ ! -f "$package_file" ]; then
        error "Configuration file not found: $package_file" "config_not_found"
    fi

    info "Loading package configuration from: $package_file"

    # Parse package configuration
    PACKAGE_NAME=$(yq eval '.package_name' "$package_file")
    GITHUB_REPO=$(yq eval '.github_repo' "$package_file")
    ARTIFACT_FORMAT=$(yq eval '.artifact_format // "tar.gz"' "$package_file")
    BINARY_PATH=$(yq eval '.binary_path // ""' "$package_file")
    
    # Simple parallel build configuration
    MAX_PARALLEL="${MAX_PARALLEL:-2}"
    PARALLEL_BUILDS="true"
    
    info "Parallel build configuration: $MAX_PARALLEL concurrent jobs"
    
    # Load default architectures from system
    DEFAULT_ARCHS="amd64 arm64 armel armhf i386 ppc64el s390x riscv64 loong64"
    
    # Parse architectures
    ARCH_COUNT=$(yq eval '.architectures | length' "$package_file" 2>/dev/null || echo "0")
    
    if [ "$ARCH_COUNT" -eq 0 ]; then
        # Use defaults - auto-discovery mode
        AUTO_DISCOVERY="true"
        ARCH_TYPE="!!default"
        info "No architectures specified, using defaults: $DEFAULT_ARCHS"
    else
        AUTO_DISCOVERY="false"
        ARCH_TYPE=$(yq eval '.architectures | type' "$package_file")
        info "Using architectures from config"
    fi
    
    # Parse distributions (with defaults)
    DISTRIBUTIONS=$(yq eval '.debian_distributions // ["bookworm", "trixie", "forky", "sid"]' "$package_file" | tr -d '[],"')
    DISTRIBUTIONS=$(echo "$DISTRIBUTIONS" | tr '\n' ' ' | sed 's/ *$//')
    
    if [ -z "$DISTRIBUTIONS" ]; then
        DISTRIBUTIONS="bookworm trixie forky sid"
        info "No distributions specified, using defaults: $DISTRIBUTIONS"
    fi
    
    info "Configuration loaded successfully"
}

# Get supported architectures
get_supported_architectures() {
    if [ "$AUTO_DISCOVERY" = "true" ]; then
        echo "$DEFAULT_ARCHS" | tr ' ' '\n'
    else
        if [ "$ARCH_TYPE" = "!!seq" ]; then
            yq eval '.architectures[]' "$CONFIG_FILE"
        else
            yq eval '.architectures | keys | .[]' "$CONFIG_FILE"
        fi
    fi
}

# Architecture validation
is_arch_supported_for_dist() {
    local arch="$1"
    local dist="$2"
    
    # Load universal architectures from system configuration
    local universal_archs=$(yq eval '.architecture_support.universal[]' "$SCRIPT_DIR/data/system.yaml" 2>/dev/null | tr '\n' ' ')
    if echo "$universal_archs" | grep -qw "$arch"; then
        return 0
    fi
    
    # Architecture-specific rules from system.yaml
    local supported_dists=$(yq eval ".architecture_support.restricted.\"$arch\".distributions[]" "$SCRIPT_DIR/data/system.yaml" 2>/dev/null | tr '\n' ' ')
    if [ -n "$supported_dists" ] && echo "$supported_dists" | grep -qw "$dist"; then
        return 0
    fi
    
    return 1
}