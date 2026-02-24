#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize variables
CONFIG_FILE=""
VERSION=""
BUILD_VERSION=""
ARCH="all"

# Check for special flags
DRY_RUN=false
HELP=false
SETUP=false
ZERO_CONFIG=false
ZERO_CONFIG_REPO=""
ZERO_CONFIG_VERSION=""
ZERO_CONFIG_BUILD_VERSION=""

# Parse all arguments including flags with values
positional_args=()
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        --help|-h)
            HELP=true
            ;;
        --setup)
            SETUP=true
            ;;
        --auto-discovery|--ad)
            ZERO_CONFIG=true
            # Next arg should be repo
            i=$((i + 1))
            if [ $i -le $# ]; then
                ZERO_CONFIG_REPO="${!i}"
            fi
            # Next arg should be version
            i=$((i + 1))
            if [ $i -le $# ]; then
                ZERO_CONFIG_VERSION="${!i}"
            fi
            # Next arg should be build version
            i=$((i + 1))
            if [ $i -le $# ]; then
                ZERO_CONFIG_BUILD_VERSION="${!i}"
            fi
            ;;
        -*)
            positional_args+=("$arg")
            ;;
        *)
            positional_args+=("$arg")
            ;;
    esac
    i=$((i + 1))
done

# If we have positional args, use them
if [ ${#positional_args[@]} -ge 3 ]; then
    CONFIG_FILE="${positional_args[0]}"
    VERSION="${positional_args[1]}"
    BUILD_VERSION="${positional_args[2]}"
    ARCH="${positional_args[3]:-all}"
fi

# Flag to prevent double error handling
ERROR_HANDLED=false

# Error handling with telemetry
handle_build_error() {
    local exit_code=$?
    local line_number=$1

    # Prevent double error handling
    if [ "$ERROR_HANDLED" = "true" ]; then
        return
    fi
    ERROR_HANDLED=true

    # Record failure in telemetry (if telemetry is loaded)
    if declare -f record_build_failure >/dev/null 2>&1; then
        record_build_failure "script_execution" "Build failed at line $line_number with exit code $exit_code" "$exit_code"
        finalize_telemetry
    fi

    # Cleanup on error
    cleanup_api_cache 2>/dev/null || true
    cleanup_lintian_results 2>/dev/null || true

    # Only show generic error if no specific error was shown
    # (the specific error function already printed details)
    if [ -z "$SPECIFIC_ERROR_SHOWN" ]; then
        echo -e "\033[0;31m❌ ERROR: Build failed with exit code $exit_code at line $line_number\033[0m" >&2
    fi
    
    exit $exit_code
}

# Set error trap
trap 'handle_build_error $LINENO' ERR

# Initialize lazy loading system (optimizes startup time)
source "$SCRIPT_DIR/lib/lazy-loading.sh"

# Preload essential libraries that are always needed
load_essential_libraries

# Set global variables before loading optional libraries
TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-false}"
LINTIAN_CHECK="${LINTIAN_CHECK:-false}"

# Preload feature-specific libraries based on configuration
preload_feature_libraries "build"

# Show help if requested
if [ "$HELP" = "true" ]; then
    echo "Usage: $0 <config-file> <version> <build-version> [architecture] [options]"
    echo ""
    echo "Arguments:"
    echo "  config-file     Path to multiarch-config.yaml"
    echo "  version         Version to build (e.g., 0.9.3)"
    echo "  build-version   Debian build version (e.g., 1)"
    echo "  architecture    Target architecture or 'all' (default: all)"
    echo ""
    echo "Options:"
    echo "  --dry-run              Validate configuration without building"
    echo "  --help, -h             Show this help message"
    echo "  --setup                Run interactive setup wizard"
    echo "  --auto-discovery, --ad Build without config file (auto-detect from GitHub repo)"
    echo ""
    echo "Examples:"
    echo "  $0 config.yaml 2.35.0 1 arm64              # Build for arm64 only"
    echo "  $0 config.yaml 2.35.0 1 all                # Build for all architectures"
    echo "  $0 config.yaml 2.35.0 1 all --dry-run      # Validate config without building"
    echo "  $0 --setup                                 # Interactive setup wizard"
    echo "  $0 --auto-discovery eza-community/eza v0.18.0 1  # Build without config"
    echo "  $0 --ad sharkdp/bat v0.24.0 1              # Shorthand for auto-discovery"
    echo ""
    echo "Supported architectures: amd64, arm64, armel, armhf, i386, ppc64el, s390x, riscv64, loong64"
    echo ""
    echo "Environment Variables:"
    echo "  MAX_PARALLEL    Maximum concurrent builds (default: 2, recommended: 2-4)"
    echo "  PARALLEL_BUILDS Enable parallel builds (default: true)"
    echo "  TELEMETRY_ENABLED Enable build telemetry (default: true)"
    echo "  LINTIAN_CHECK   Enable lintian package validation (default: false)"
    echo ""
    echo "Quick Start:"
    echo "  1. Run setup wizard: $0 --setup"
    echo "  2. Or use template:  cp templates/rust/eza.yaml .github/build-config.yaml"
    echo "  3. Or auto-discovery: $0 --ad owner/repo version 1"
    exit 0
fi

# Usage validation
if [ -z "$CONFIG_FILE" ] || [ -z "$VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    # Check for setup wizard
    if [ "$SETUP" = "true" ]; then
        source "$SCRIPT_DIR/lib/zero-config.sh"
        run_setup_wizard
        exit $?
    fi
    
    # Check for auto-discovery build
    if [ "$ZERO_CONFIG" = "true" ]; then
        if [ -z "$ZERO_CONFIG_REPO" ]; then
            echo "Error: --auto-discovery requires a GitHub repository (owner/repo)"
            echo ""
            echo "Usage: $0 --auto-discovery owner/repo version build-version [architecture]"
            echo "Example: $0 --ad eza-community/eza v0.18.0 1"
            exit 1
        fi
        
        source "$SCRIPT_DIR/lib/zero-config.sh"
        zero_config_build "$ZERO_CONFIG_REPO" "$ZERO_CONFIG_VERSION" "$ZERO_CONFIG_BUILD_VERSION" "$ARCH"
        exit $?
    fi
    
    echo "Usage: $0 <config-file> <version> <build-version> [architecture]"
    echo ""
    echo "Arguments:"
    echo "  config-file     Path to multiarch-config.yaml"
    echo "  version         Version to build (e.g., 0.9.3)"
    echo "  build-version   Debian build version (e.g., 1)"
    echo "  architecture    Target architecture or 'all' (default: all)"
    echo ""
    echo "Quick Start Options:"
    echo "  --setup                Interactive setup wizard (recommended for first time)"
    echo "  --auto-discovery, --ad Auto-detect from GitHub (no config needed)"
    echo "  --help, -h             Show full help message"
    echo ""
    echo "Examples:"
    echo "  $0 --setup                               # Interactive setup"
    echo "  $0 --ad eza-community/eza v0.18.0 1      # Auto-discovery build"
    echo "  $0 config.yaml 2.35.0 1 arm64            # Traditional build"
    echo ""
    echo "Supported architectures: amd64, arm64, armel, armhf, i386, ppc64el, s390x, riscv64, loong64"
    exit 1
fi

# Run dry-run mode if requested
if [ "$DRY_RUN" = "true" ]; then
    source "$SCRIPT_DIR/lib/dry-run.sh"
    run_dry_run "$CONFIG_FILE" "$VERSION" "$BUILD_VERSION" "$ARCH"
    exit $?
fi

# Parse and validate configuration
parse_config "$CONFIG_FILE"

# If auto-detection was needed and we now have access to discovery functions
if [ "$ARTIFACT_FORMAT_AUTO_DETECT_NEEDED" = "true" ]; then
    info "Performing artifact format auto-detection..."
    
    # Try to detect the format by checking available architectures and release patterns
    arch_array_str=$(get_supported_architectures)
    if [ -n "$arch_array_str" ]; then
        readarray -t arch_array <<< "$arch_array_str"
        # Try to detect format from the first available architecture
        first_arch="${arch_array[0]}"
        release_pattern=$(get_release_pattern "$first_arch" 2>&1)
        
        if [ -n "$release_pattern" ]; then
            # Use the detection function from discovery.sh
            detected_format=$(detect_artifact_format "$release_pattern")
            if [ $? -eq 0 ] && [ -n "$detected_format" ]; then
                ARTIFACT_FORMAT="$detected_format"
                info "Auto-detected artifact format: $ARTIFACT_FORMAT (from: $release_pattern)"
            else
                info "Could not determine format from release pattern, using default: tar.gz"
                ARTIFACT_FORMAT="tar.gz"
            fi
        else
            # Try to get any pattern by forcing auto-discovery for the first architecture
            # We'll try to get the first pattern from the actual release assets
            assets=$(fetch_release_assets 2>/dev/null)
            if [ -n "$assets" ]; then
                # Get the first asset to detect format
                first_asset=$(echo "$assets" | head -1)
                if [ -n "$first_asset" ]; then
                    detected_format=$(detect_artifact_format "$first_asset")
                    if [ $? -eq 0 ] && [ -n "$detected_format" ]; then
                        ARTIFACT_FORMAT="$detected_format"
                        info "Auto-detected artifact format: $ARTIFACT_FORMAT (from first release asset: $first_asset)"
                    else
                        info "Could not determine format from first release asset, using default: tar.gz"
                        ARTIFACT_FORMAT="tar.gz"
                    fi
                else
                    info "No release assets found, using default: tar.gz"
                    ARTIFACT_FORMAT="tar.gz"
                fi
            else
                info "Could not fetch release assets for detection, using default: tar.gz"
                ARTIFACT_FORMAT="tar.gz"
            fi
        fi
    else
        info "No architectures defined for detection, using default: tar.gz"
        ARTIFACT_FORMAT="tar.gz"
    fi
fi

# Check for required tools
check_requirements

# Record build start time
BUILD_START_TIME=$(date +%s)

# Initialize telemetry system
init_telemetry

# Initialize lintian results tracking (placeholder)
:  # No-op for now

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

    # Initialize tracking files
    echo "" > /tmp/attempted_architectures.txt
    echo "" > /tmp/skipped_architectures.txt
    echo "" > /tmp/available_architectures.txt

    # Pre-detect available architectures for this version
    info "Detecting available architectures for $PACKAGE_NAME version $VERSION..."
    for arch in "${ARCH_ARRAY[@]}"; do
        # Check if this architecture has release assets available
        pattern=$(get_release_pattern "$arch" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$pattern" ]; then
            echo "$arch" >> /tmp/available_architectures.txt
            info "  ✓ $arch: Available"
        else
            info "  ✗ $arch: Not available (no matching release assets)"
        fi
    done

    BUILD_SUCCESS=false
    if [ "$PARALLEL_BUILDS" = "true" ]; then
        # Initialize CI optimization for dynamic parallelism
        source "$SCRIPT_DIR/ci-optimization.sh"
        init_ci_optimization

        # Apply dynamic parallelism based on available resources
        # Priority: MAX_PARALLEL env var > config file > auto-detected optimal
        if [ -z "$MAX_PARALLEL" ]; then
            MAX_PARALLEL="$OPTIMIZED_PARALLEL_JOBS"
            info "Dynamic parallelism: Using $MAX_PARALLEL concurrent jobs (auto-detected from system resources)"
        else
            # Validate user-specified MAX_PARALLEL against system capacity
            if [ "$MAX_PARALLEL" -gt "$OPTIMIZED_PARALLEL_JOBS" ]; then
                warning "Requested $MAX_PARALLEL parallel jobs exceeds system capacity ($OPTIMIZED_PARALLEL_JOBS)"
                warning "Limiting to $OPTIMIZED_PARALLEL_JOBS parallel jobs to prevent resource exhaustion"
                MAX_PARALLEL="$OPTIMIZED_PARALLEL_JOBS"
            fi
            info "Using $MAX_PARALLEL concurrent jobs (user-specified, resource-validated)"
        fi

        # Export MAX_PARALLEL for orchestration and resource pooling
        export MAX_PARALLEL

        # Execute parallel builds with advanced resource pooling
        if build_all_architectures_parallel "${ARCH_ARRAY[@]}"; then
            BUILD_SUCCESS=true
        else
            # Parallel build failed - check if any packages were generated
            TOTAL_PACKAGES=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | wc -l)
            if [ "$TOTAL_PACKAGES" -eq 0 ]; then
                BUILD_SUCCESS=false
            fi
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

            # Calculate actual attempted vs built based on detected available architectures
            attempted_archs=$(cat /tmp/attempted_architectures.txt 2>/dev/null | wc -l || echo 0)
            skipped_archs=$(cat /tmp/skipped_architectures.txt 2>/dev/null | wc -l || echo 0)
            available_archs=$(cat /tmp/available_architectures.txt 2>/dev/null | wc -l || echo 0)

            # Calculate target packages based on available architectures and their distribution support
            attempted_packages=0
            for arch in $(cat /tmp/attempted_architectures.txt 2>/dev/null); do
                # Get distribution support for this architecture
                supported_count=0
                for dist in "bookworm" "trixie" "forky" "sid"; do
                    if is_arch_supported_for_dist "$arch" "$dist"; then
                        supported_count=$((supported_count + 1))
                    fi
                done
                attempted_packages=$((attempted_packages + supported_count))
            done

            if [ "$attempted_packages" -gt 0 ]; then
                SUCCESS_RATE=$(( (TOTAL_PACKAGES * 100) / attempted_packages ))
            else
                SUCCESS_RATE=0
            fi

            if [ "$TOTAL_PACKAGES" -eq "$attempted_packages" ]; then
                echo "🎉 All attempted architectures built successfully!"
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
            echo "  🔍 Detected: $available_archs architectures available for $VERSION"
            echo "  🎯 Attempted: $attempted_packages packages ($attempted_archs architectures)"
            echo "  ✅ Built: $TOTAL_PACKAGES packages"
            echo "  📈 Success Rate: $SUCCESS_RATE%"
            # Show which distributions were successfully built
            built_dists=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | sed 's/.*+\([^_]*\)_[^_]*\.deb/\1/' | sort -u | tr '\n' ' ' | sed 's/ *$//')
            if [ -n "$built_dists" ]; then
                echo "  ✅ Built for distributions: $built_dists"
            fi

            # Show which architectures were built (extract from package names)
            built_archs=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | sed 's/.*+\([^_]*\)_\([^\.]*\)\.deb/\2/' | sort -u | tr '\n' ' ' | sed 's/ *$//')
            if [ -n "$built_archs" ]; then
                echo "  🏗️  Built architectures: $built_archs"
            fi

            # Show which architectures were not available for this version
            if [ "$skipped_archs" -gt 0 ]; then
                skipped_list=$(cat /tmp/skipped_architectures.txt 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
                echo "  ⚠️  Skipped architectures (no release assets): $skipped_list"
            fi

            echo ""
            echo "✅ Total: $TOTAL_PACKAGES packages successfully built"

            # Record successful completion in telemetry
            if [ "$TOTAL_PACKAGES" -eq "$attempted_packages" ]; then
                record_build_stage_complete "build_completion" "success" "All attempted builds completed successfully"
            else
                record_build_stage_complete "build_completion" "partial_success" "Build completed with $TOTAL_PACKAGES/$attempted_packages packages ($SUCCESS_RATE% success rate)"
            fi

            # Show resource usage summary
            if [ "$TELEMETRY_ENABLED" = "true" ] && [ -f ".telemetry/current-peak-memory.txt" ]; then
                peak_mem=$(cat .telemetry/current-peak-memory.txt 2>/dev/null || echo "0")
                peak_cpu=$(cat .telemetry/current-peak-cpu.txt 2>/dev/null || echo "0")
                if [ "$peak_mem" -gt 0 ] || [ "$peak_cpu" -gt 0 ]; then
                    echo "  📊 Resource Usage: Peak ${peak_mem}MB memory, Peak ${peak_cpu}% CPU"
                fi
            fi

            # Generate build summary JSON (after telemetry is finalized)
            generate_build_summary
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
