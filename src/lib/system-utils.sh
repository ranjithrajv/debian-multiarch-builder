#!/bin/bash

# System validation and utilities

# Architecture validation utilities
calculate_supported_distributions() {
    local arch="$1"
    local dists="${2:-bookworm trixie forky sid}"
    local supported_count=0

    for dist in $dists; do
        if is_arch_supported_for_dist "$arch" "$dist"; then
            supported_count=$((supported_count + 1))
        fi
    done

    echo "$supported_count"
}

# Validation utilities
validate_version_format() {
    local version="$1"

    # Accept semantic versioning and common version patterns
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9]+)?(\.[0-9]+)?$ ]]; then
        error "Invalid version format: $version (expected: 1.0.0, 2.1, 3.0.0-beta1, etc.)"
    fi

    return 0
}

validate_architecture_name() {
    local arch="$1"
    local valid_archs="amd64 arm64 armel armhf i386 ppc64el s390x riscv64 loong64"

    if ! echo "$valid_archs" | grep -qw "$arch"; then
        error "Invalid architecture: $arch (valid: $valid_archs)"
    fi

    return 0
}

validate_distribution_name() {
    local dist="$1"
    local valid_dists="bookworm trixie forky sid"

    if ! echo "$valid_dists" | grep -qw "$dist"; then
        error "Invalid distribution: $dist (valid: $valid_dists)"
    fi

    return 0
}