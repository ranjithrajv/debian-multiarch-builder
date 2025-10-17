#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all library modules
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/github-api.sh"
source "$SCRIPT_DIR/lib/discovery.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/build.sh"
source "$SCRIPT_DIR/lib/parallel.sh"
source "$SCRIPT_DIR/lib/summary.sh"

# Parse command-line arguments
CONFIG_FILE=$1
VERSION=$2
BUILD_VERSION=$3
ARCH=${4:-all}

# Usage validation
if [ -z "$CONFIG_FILE" ] || [ -z "$VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <config-file> <version> <build-version> [architecture]"
    echo ""
    echo "Arguments:"
    echo "  config-file     Path to multiarch-config.yaml"
    echo "  version         Version to build (e.g., 0.9.3)"
    echo "  build-version   Debian build version (e.g., 1)"
    echo "  architecture    Target architecture or 'all' (default: all)"
    echo ""
    echo "Examples:"
    echo "  $0 config.yaml 2.35.0 1 arm64    # Build for arm64 only"
    echo "  $0 config.yaml 2.35.0 1 all      # Build for all architectures"
    echo ""
    echo "Supported architectures: amd64, arm64, armel, armhf, i386, ppc64el, s390x, riscv64"
    exit 1
fi

# Parse and validate configuration
parse_config "$CONFIG_FILE"

# Check for required tools
check_requirements

# Record build start time
BUILD_START_TIME=$(date +%s)

info "Building $PACKAGE_NAME version $VERSION"
info "GitHub repo: $GITHUB_REPO"
info "Distributions: $DISTRIBUTIONS"
info "Architectures defined: $ARCH_COUNT"
echo ""

# Main build logic
if [ "$ARCH" = "all" ]; then
    echo "🚀 Building $PACKAGE_NAME $VERSION-$BUILD_VERSION for all supported architectures..."

    # Get all supported architectures from config
    ARCHITECTURES=$(get_supported_architectures)
    ARCH_ARRAY=($ARCHITECTURES)
    TOTAL_ARCHS=${#ARCH_ARRAY[@]}

    if [ "$PARALLEL_BUILDS" = "true" ]; then
        build_all_architectures_parallel "${ARCH_ARRAY[@]}"
    else
        # Sequential builds (original behavior)
        build_architecture_sequential "${ARCH_ARRAY[@]}"
    fi

    echo ""
    echo "=========================================="
    echo "🎉 All architectures built successfully!"
    echo "=========================================="
    echo ""
    echo "Generated packages:"
    ls -lh ${PACKAGE_NAME}_*.deb | awk '{print "  " $9 " (" $5 ")"}'
    echo ""
    TOTAL_PACKAGES=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | wc -l)
    echo "✅ Total: $TOTAL_PACKAGES packages"

    # Generate build summary JSON
    generate_build_summary
else
    # Build for single architecture
    echo "Building for single architecture: $ARCH"
    echo ""

    if ! build_architecture "$ARCH"; then
        exit 1
    fi

    echo ""
    echo "Generated packages:"
    ls -lh ${PACKAGE_NAME}_*.deb | awk '{print "  " $9 " (" $5 ")"}'
    echo ""
    TOTAL_PACKAGES=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | wc -l)
    echo "✅ Total: $TOTAL_PACKAGES packages"

    # Generate build summary JSON
    ARCHITECTURES=$ARCH
    generate_build_summary
fi
