#!/bin/bash

# Core validation functions

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

# Validate build environment
validate_build_environment() {
    # Check available disk space (minimum 2GB)
    local available_space=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$available_space" -lt 2 ]; then
        warning "Low disk space: ${available_space}GB available (minimum 2GB recommended)"
    fi

    # Check available memory (minimum 1GB free)
    local available_memory=$(free -m | awk '/^Mem:/ {print $7}')
    if [ "$available_memory" -lt 1024 ]; then
        warning "Low memory: ${available_memory}MB available (minimum 1GB recommended)"
    fi

    # Check if we can write to current directory
    if ! touch .test_write_permission 2>/dev/null; then
        error "Cannot write to current directory. Check permissions."
    fi
    rm -f .test_write_permission

    # Validate Docker is working
    if ! docker run --rm hello-world >/dev/null 2>&1; then
        error "Docker is not functioning properly. Cannot run hello-world container."
    fi
}

# Comprehensive validation of all inputs
validate_all_inputs() {
    local config_file="$1"
    local version="$2"
    local build_version="$3"
    local architecture="$4"

    info "Starting comprehensive validation..."

    # Validate version and build version
    validate_version_format "$version"
    validate_build_version "$build_version"

    # Validate architecture if specified
    if [ "$architecture" != "all" ]; then
        validate_architecture_name "$architecture"
    fi

    # Validate build environment
    validate_build_environment

    info "All validations passed successfully!"
    return 0
}

# Validate build version
validate_build_version() {
    local build_version="$1"

    # Build version should be a positive integer
    if [[ ! "$build_version" =~ ^[1-9][0-9]*$ ]]; then
        error "Invalid build_version: $build_version (must be a positive integer)"
    fi

    info "Build version is valid: $build_version"
}

# Export validation functions
export -f check_requirements
export -f validate_build_environment
export -f validate_all_inputs
export -f validate_build_version