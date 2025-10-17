#!/bin/bash

# Configuration parsing and validation functions

# Parse and validate configuration
parse_config() {
    local config_file=$1

    # Check if config file exists
    if [ ! -f "$config_file" ]; then
        error "Configuration file not found: $config_file"
    fi

    # Check if yq is installed
    if ! command -v yq &> /dev/null; then
        error "yq is not installed. Please install yq: https://github.com/mikefarah/yq"
    fi

    # Validate YAML syntax
    if ! yq eval '.' "$config_file" &> /dev/null; then
        error "Invalid YAML syntax in $config_file"
    fi

    # Parse and validate configuration
    PACKAGE_NAME=$(yq eval '.package_name' "$config_file")
    GITHUB_REPO=$(yq eval '.github_repo' "$config_file")
    ARTIFACT_FORMAT=$(yq eval '.artifact_format // "tar.gz"' "$config_file")
    BINARY_PATH=$(yq eval '.binary_path // ""' "$config_file")
    PARALLEL_BUILDS=$(yq eval '.parallel_builds // true' "$config_file")
    MAX_PARALLEL=$(yq eval '.max_parallel // 2' "$config_file")

    # Validate required fields
    if [ "$PACKAGE_NAME" = "null" ] || [ -z "$PACKAGE_NAME" ]; then
        error "Missing required field 'package_name' in $config_file"
    fi

    if [ "$GITHUB_REPO" = "null" ] || [ -z "$GITHUB_REPO" ]; then
        error "Missing required field 'github_repo' in $config_file"
    fi

    # Validate GitHub repo format
    if [[ ! "$GITHUB_REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid github_repo format: $GITHUB_REPO (expected: owner/repo)"
    fi

    # Get and validate distributions
    DISTRIBUTIONS=$(yq eval '.debian_distributions[]' "$config_file" 2>/dev/null | tr '\n' ' ')
    if [ -z "$DISTRIBUTIONS" ] || [ "$DISTRIBUTIONS" = "null" ]; then
        error "Missing or empty 'debian_distributions' in $config_file"
    fi

    # Validate distribution names
    VALID_DISTS="bookworm trixie forky sid"
    for dist in $DISTRIBUTIONS; do
        if ! echo "$VALID_DISTS" | grep -qw "$dist"; then
            warning "Unknown distribution: $dist (valid: $VALID_DISTS)"
        fi
    done

    # Validate artifact format
    case "$ARTIFACT_FORMAT" in
        "tar.gz"|"tgz"|"zip")
            ;;
        *)
            error "Unsupported artifact_format: $ARTIFACT_FORMAT (supported: tar.gz, tgz, zip)"
            ;;
    esac

    # Check if any architectures are defined
    ARCH_COUNT=$(yq eval '.architectures | length' "$config_file")
    if [ "$ARCH_COUNT" = "0" ] || [ "$ARCH_COUNT" = "null" ]; then
        error "No architectures defined in $config_file"
    fi

    # Detect architecture configuration mode (list vs object)
    ARCH_TYPE=$(yq eval '.architectures | type' "$config_file")
    if [ "$ARCH_TYPE" = "!!seq" ]; then
        AUTO_DISCOVERY=true
        info "Auto-discovery mode enabled (architectures specified as list)"
    elif [ "$ARCH_TYPE" = "!!map" ]; then
        AUTO_DISCOVERY=false
        info "Manual mode (architectures with release_pattern)"
    else
        error "Invalid architectures format in $config_file (must be list or object)"
    fi
}

# Check for required tools
check_requirements() {
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
    fi

    if ! docker ps &> /dev/null; then
        error "Docker daemon is not running or you don't have permission to access it"
    fi
}

# Function to get all supported architectures from config
get_supported_architectures() {
    if [ "$AUTO_DISCOVERY" = "true" ]; then
        # List format: architectures are array items
        yq eval '.architectures[]' "$CONFIG_FILE"
    else
        # Object format: architectures are keys
        yq eval '.architectures | keys | .[]' "$CONFIG_FILE"
    fi
}

# Function to check if architecture is supported for a distribution
is_arch_supported_for_dist() {
    local arch=$1
    local dist=$2

    # Check if there's a distribution override
    local override_dists=$(yq eval ".distribution_arch_overrides.${arch}.distributions[]" "$CONFIG_FILE" 2>/dev/null)

    if [ "$override_dists" != "null" ] && [ -n "$override_dists" ]; then
        # If override exists, check if dist is in the list
        echo "$override_dists" | grep -q "^${dist}$"
        return $?
    fi

    # No override, all distributions supported
    return 0
}
