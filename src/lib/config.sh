#!/bin/bash

# Configuration parsing and validation functions

# Source YAML utilities for loading externalized configuration
source "$SCRIPT_DIR/data/yaml-utils.sh"

# Load architecture support data
load_architecture_support

# Parse and validate configuration
parse_config() {
    local config_file=$1
    local config_dir=$(dirname "$config_file")

    # Initialize CI environment detection first
    source "$SCRIPT_DIR/ci-optimization.sh"
    init_ci_optimization

    # New split configuration: package.yaml + optional overrides.yaml
    local package_file="$config_file"
    local overrides_file="$config_dir/overrides.yaml"

    info "Loading package configuration from: $package_file"

    # Check if package file exists
    if [ ! -f "$package_file" ]; then
        error "Configuration file not found: $package_file"
    fi

    # Check if yq is installed
    if ! command -v yq &> /dev/null; then
        error "yq is not installed. Please install yq: https://github.com/mikefarah/yq"
    fi

    # Validate YAML syntax for package file
    if ! yq eval '.' "$package_file" &> /dev/null; then
        error "Invalid YAML syntax in $package_file"
    fi

    # Validate YAML syntax for overrides file if it exists
    if [ -f "$overrides_file" ]; then
        info "Loading overrides from: $overrides_file"
        if ! yq eval '.' "$overrides_file" &> /dev/null; then
            error "Invalid YAML syntax in $overrides_file"
        fi
    fi

    # Parse package configuration
    PACKAGE_NAME=$(yq eval '.package_name' "$package_file")
    GITHUB_REPO=$(yq eval '.github_repo' "$package_file")
    ARTIFACT_FORMAT=$(yq eval '.artifact_format // "tar.gz"' "$package_file")
    BINARY_PATH=$(yq eval '.binary_path // ""' "$package_file")

    # Parse parallel builds settings from overrides or package file
    if [ -f "$overrides_file" ]; then
        PARALLEL_BUILDS=$(yq eval '.parallel_builds // true' "$overrides_file")
        # MAX_PARALLEL priority: env var > overrides file > package file > default
        if [ -z "$MAX_PARALLEL" ]; then
            MAX_PARALLEL=$(yq eval '.max_parallel // 2' "$overrides_file")
        fi
    else
        PARALLEL_BUILDS=$(yq eval '.parallel_builds // true' "$package_file")
        # MAX_PARALLEL priority: env var > package file > default
        if [ -z "$MAX_PARALLEL" ]; then
            MAX_PARALLEL=$(yq eval '.max_parallel // 2' "$package_file")
        fi
    fi

    # Apply CI optimizations to MAX_PARALLEL
    if [ -z "$MAX_PARALLEL" ]; then
        # Use CI-optimized defaults if not specified
        MAX_PARALLEL=$(apply_ci_optimizations "2")
    else
        # Apply resource-based limits to user-specified value
        MAX_PARALLEL=$(apply_ci_optimizations "$MAX_PARALLEL")
    fi

    info "Parallel build configuration: $MAX_PARALLEL concurrent jobs (CI-optimized)"

    # Validate build environment
    validate_build_environment

    # Generate CI environment report if in CI
    if [ "$IS_CI_ENVIRONMENT" = "true" ]; then
        generate_ci_environment_report
    fi

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

    # Get distributions (default to all valid distributions from system.yaml)
    DISTRIBUTIONS=$(yq eval '.debian_distributions[]' "$package_file" 2>/dev/null | tr '\n' ' ')
    if [ -z "$DISTRIBUTIONS" ] || [ "$DISTRIBUTIONS" = "null" ]; then
        # Load default distributions from system.yaml
        local system_yaml="$SCRIPT_DIR/system.yaml"
        DISTRIBUTIONS=$(yq eval '.distributions.valid[]' "$system_yaml" 2>/dev/null | tr '\n' ' ')
        info "No distributions specified, using defaults: $DISTRIBUTIONS"
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

    # Get architectures (default to all architectures from system.yaml)
    ARCH_COUNT=$(yq eval '.architectures | length' "$package_file")
    if [ "$ARCH_COUNT" = "0" ] || [ "$ARCH_COUNT" = "null" ]; then
        # Load default architectures from system.yaml (universal + restricted)
        local system_yaml="$SCRIPT_DIR/system.yaml"
        local universal_archs=$(yq eval '.architecture_support.universal[]' "$system_yaml" 2>/dev/null | tr '\n' ' ')
        local restricted_archs=$(yq eval '.architecture_support.restricted | keys | .[]' "$system_yaml" 2>/dev/null | tr '\n' ' ')

        # Create a default architectures list in the package file format
        DEFAULT_ARCHS="$universal_archs $restricted_archs"
        info "No architectures specified, using defaults: $DEFAULT_ARCHS"

        # Store in CONFIG_FILE for get_supported_architectures to use
        ARCH_TYPE="!!default"
        AUTO_DISCOVERY=true
    else
        # Detect architecture configuration mode (list vs object)
        ARCH_TYPE=$(yq eval '.architectures | type' "$package_file")
        if [ "$ARCH_TYPE" = "!!seq" ]; then
            AUTO_DISCOVERY=true
            info "Auto-discovery mode enabled (architectures specified as list)"
        elif [ "$ARCH_TYPE" = "!!map" ]; then
            AUTO_DISCOVERY=false
            info "Manual mode (architectures with release_pattern)"
        else
            error "Invalid architectures format in $package_file (must be list or object)"
        fi
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
    if [ "$ARCH_TYPE" = "!!default" ]; then
        # Using defaults from system.yaml
        echo "$DEFAULT_ARCHS" | tr ' ' '\n'
    elif [ "$AUTO_DISCOVERY" = "true" ]; then
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
    local config_dir=$(dirname "$CONFIG_FILE")
    local overrides_file="$config_dir/overrides.yaml"

    # First check user-defined overrides (takes precedence)
    local override_dists=""

    # Check overrides.yaml first if it exists
    if [ -f "$overrides_file" ]; then
        override_dists=$(yq eval ".distribution_arch_overrides.${arch}.distributions[]" "$overrides_file" 2>/dev/null)
    fi

    # Fall back to checking the main config file if not found in overrides
    if [ -z "$override_dists" ] || [ "$override_dists" = "null" ]; then
        override_dists=$(yq eval ".distribution_arch_overrides.${arch}.distributions[]" "$CONFIG_FILE" 2>/dev/null)
    fi

    if [ "$override_dists" != "null" ] && [ -n "$override_dists" ]; then
        # User override exists, check if dist is in the list
        echo "$override_dists" | grep -q "^${dist}$"
        return $?
    fi

    # Use YAML-based function for built-in Debian distribution rules
    is_arch_supported_for_dist_from_yaml "$arch" "$dist"
}
