#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Error handling with telemetry
handle_build_error() {
    local exit_code=$?
    local line_number=$1

    # Record failure in telemetry
    record_build_failure "script_execution" "Build failed at line $line_number with exit code $exit_code" "$exit_code"
    finalize_telemetry

    # Cleanup on error
    cleanup_api_cache
    cleanup_lintian_results

    error "Build failed with exit code $exit_code at line $line_number"
    exit $exit_code
}

# Set error trap
trap 'handle_build_error $LINENO' ERR

# Source all library modules
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/github-api.sh"
source "$SCRIPT_DIR/lib/discovery.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/lintian.sh"
source "$SCRIPT_DIR/lib/telemetry.sh"
source "$SCRIPT_DIR/lib/build.sh"
source "$SCRIPT_DIR/lib/orchestration.sh"
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

# Initialize telemetry system
init_telemetry

# Initialize lintian results tracking
init_lintian_results

# Record build start telemetry
record_build_stage "build_initialization"

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

      BUILD_SUCCESS=false
    if [ "$PARALLEL_BUILDS" = "true" ]; then
        if build_all_architectures_parallel "${ARCH_ARRAY[@]}"; then
            BUILD_SUCCESS=true
        fi
    else
        # Sequential builds (original behavior)
        if build_architecture_sequential "${ARCH_ARRAY[@]}"; then
            BUILD_SUCCESS=true
        fi
    fi

    # Check if builds actually succeeded before showing success message
    if [ "$BUILD_SUCCESS" = "true" ]; then
        # Verify we actually have packages built
        TOTAL_PACKAGES=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | wc -l)
        if [ "$TOTAL_PACKAGES" -gt 0 ]; then
            echo ""
            echo "=========================================="

            # Calculate what was built vs what was attempted
            TARGET_PACKAGES=$((TOTAL_ARCHS * 4))  # 4 distributions per architecture
            SUCCESS_RATE=$(( (TOTAL_PACKAGES * 100) / TARGET_PACKAGES ))

            if [ "$TOTAL_PACKAGES" -eq "$TARGET_PACKAGES" ]; then
                echo "🎉 All architectures built successfully!"
            elif [ "$TOTAL_PACKAGES" -gt 0 ]; then
                echo "✅ Build completed with partial success ($SUCCESS_RATE% success rate)"
            else
                echo "⚠️  Build completed but no packages were generated!"
            fi

            echo "=========================================="
            echo ""

            # Show what was built
            echo "Generated packages:"
            ls -lh ${PACKAGE_NAME}_*.deb | awk '{print "  " $9 " (" $5 ")"}'
            echo ""

            # Show build summary
            echo "📊 Build Summary:"
            echo "  🎯 Target: $TARGET_PACKAGES packages ($TOTAL_ARCHS architectures × 4 distributions)"
            echo "  ✅ Built: $TOTAL_PACKAGES packages"
            echo "  📈 Success Rate: $SUCCESS_RATE%"

            # Show which architectures succeeded
            local built_archs=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | sed "s/.*${PACKAGE_NAME}_.*+\([^-]*\)_.*\.deb/\1/" | sort -u)
            if [ -n "$built_archs" ]; then
                echo "  ✅ Successful Architectures: $built_archs"
            fi

            # Show which architectures failed (if any)
            local failed_archs=""
            for arch in $ARCHITECTURES; do
                if ! echo "$built_archs" | grep -q "$arch"; then
                    failed_archs="$failed_archs $arch"
                fi
            done
            if [ -n "$failed_archs" ]; then
                echo "  ❌ Skipped/Failed Architectures:$failed_archs"
            fi

            echo ""
            echo "✅ Total: $TOTAL_PACKAGES packages successfully built"

            # Generate build summary JSON
            generate_build_summary

            # Record successful completion in telemetry
            if [ "$TOTAL_PACKAGES" -eq "$TARGET_PACKAGES" ]; then
                record_build_stage_complete "build_completion" "success" "All builds completed successfully"
            else
                record_build_stage_complete "build_completion" "partial_success" "Build completed with $TOTAL_PACKAGES/$TARGET_PACKAGES packages ($SUCCESS_RATE% success rate)"
            fi
        else
            # Build functions returned success but no packages were created
            echo ""
            echo "=========================================="
            echo "❌ Build completed but no packages were generated!"
            echo "=========================================="
            echo ""
            echo "This may indicate an issue with the build process."

            # Record failure in telemetry
            record_build_failure "build_validation" "Build completed but no packages were generated" "1"

            # Generate build summary JSON showing failure
            generate_build_summary

            exit 1
        fi
    else
        # Build failed - don't show success message
        echo ""
        echo "=========================================="
        echo "❌ Build failed during architecture processing!"
        echo "=========================================="
        echo ""
        TOTAL_PACKAGES=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | wc -l)
        if [ "$TOTAL_PACKAGES" -gt 0 ]; then
            echo "Some packages were generated before failure:"
            ls -lh ${PACKAGE_NAME}_*.deb | awk '{print "  " $9 " (" $5 ")"}'
            echo ""
            echo "⚠️  Partial: $TOTAL_PACKAGES packages (build incomplete)"
        else
            echo "No packages were generated."
        fi

        # Generate build summary JSON showing failure
        generate_build_summary

        # The error should already be recorded by the build functions
        exit 1
    fi
else
    # Build for single architecture
    echo "Building for single architecture: $ARCH"
    echo ""

    BUILD_SUCCESS=false
    if build_architecture "$ARCH"; then
        BUILD_SUCCESS=true
    fi

    if [ "$BUILD_SUCCESS" = "true" ]; then
        # Verify we actually have packages built
        TOTAL_PACKAGES=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | wc -l)
        if [ "$TOTAL_PACKAGES" -gt 0 ]; then
            echo ""
            echo "Generated packages:"
            ls -lh ${PACKAGE_NAME}_*.deb | awk '{print "  " $9 " (" $5 ")"}'
            echo ""
            echo "✅ Total: $TOTAL_PACKAGES packages"

            # Generate build summary JSON
            ARCHITECTURES=$ARCH
            generate_build_summary

            # Record successful completion in telemetry
            record_build_stage_complete "build_completion" "success" "Single architecture build completed successfully"
        else
            # Build returned success but no packages were created
            echo ""
            echo "=========================================="
            echo "❌ Build completed but no packages were generated!"
            echo "=========================================="
            echo ""
            echo "This may indicate an issue with the build process for architecture: $ARCH"

            # Record failure in telemetry
            record_build_failure "build_validation" "Build completed but no packages were generated for $ARCH" "1"

            # Generate build summary JSON showing failure
            ARCHITECTURES=$ARCH
            generate_build_summary

            cleanup_api_cache
            exit 1
        fi
    else
        # Build failed
        echo ""
        echo "=========================================="
        echo "❌ Build failed for architecture: $ARCH!"
        echo "=========================================="
        echo ""
        TOTAL_PACKAGES=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | wc -l)
        if [ "$TOTAL_PACKAGES" -gt 0 ]; then
            echo "Some packages were generated before failure:"
            ls -lh ${PACKAGE_NAME}_*.deb | awk '{print "  " $9 " (" $5 ")"}'
            echo ""
            echo "⚠️  Partial: $TOTAL_PACKAGES packages (build incomplete)"
        else
            echo "No packages were generated."
        fi

        # Generate build summary JSON showing failure
        ARCHITECTURES=$ARCH
        generate_build_summary

        cleanup_api_cache
        exit 1
    fi
fi

# Finalize telemetry collection (success cases already recorded stage completion)
finalize_telemetry

# Save baseline if requested
if [ "${SAVE_BASELINE:-false}" = "true" ]; then
    save_as_baseline
fi

# Display lintian summary if enabled
display_lintian_summary

# Cleanup API cache files and lintian results
cleanup_api_cache
cleanup_lintian_results
