#!/bin/bash

# Build orchestration functions (parallel and sequential)

# Helper function to format duration in human-readable format
format_duration() {
    local seconds=$1
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))

    if [ $minutes -gt 0 ]; then
        echo "${minutes}m${remaining_seconds}s"
    else
        echo "${seconds}s"
    fi
}

# Function to build architecture with logging to file (for parallel builds)
build_architecture_parallel() {
    # Disable exit-on-error for backgrounded function
    set +e

    local build_arch=$1
    local log_file="build_${build_arch}.log"
    local start_time=$(date +%s)

    # Ensure status file is always written even if error() calls exit 1 deep inside build_architecture
    trap "[ ! -f \"build_${build_arch}.status\" ] && echo 'FAILED' > \"build_${build_arch}.status\"" EXIT

    # Record telemetry for this architecture build
    record_build_stage "architecture_${build_arch}"

    # Redirect all output to log file
    {
        if build_architecture "$build_arch"; then
            echo "SUCCESS" > "build_${build_arch}.status"
            record_build_stage_complete "architecture_${build_arch}" "success" "Architecture $build_arch built successfully"
        else
            echo "FAILED" > "build_${build_arch}.status"
            record_build_stage_complete "architecture_${build_arch}" "failure" "Architecture $build_arch build failed"
            record_build_failure "architecture_build" "Failed to build architecture $build_arch" "1"
            return 1
        fi
    } > "$log_file" 2>&1

    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Save duration for reporting
    echo "$duration" > "build_${build_arch}.time"

    return $exit_code
}

# Function to build all architectures sequentially
build_architecture_sequential() {
    local arch_array=("$@")
    local total_archs=${#arch_array[@]}
    local current=0

    echo "Building architectures sequentially..."
    echo ""

    for build_arch in "${arch_array[@]}"; do
        current=$((current + 1))
        echo "=========================================="
        echo "Building $current/$total_archs: $build_arch"
        echo "=========================================="

        if ! build_architecture "$build_arch"; then
            echo "❌ Failed to build for $build_arch"
            exit 1
        fi
        echo ""
    done
}

# Function to build all architectures in parallel
build_all_architectures_parallel() {
    local arch_array=("$@")
    local total_archs=${#arch_array[@]}

    # Apply enhanced resource pooling based on current system resources
    source "$SCRIPT_DIR/lib/resource-pool.sh"

    # Source progress visualization
    source "$SCRIPT_DIR/lib/progress.sh" 2>/dev/null || true

    local current_memory_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo "2048")
    local current_cores=$(nproc 2>/dev/null || echo "2")

    # Initialize resource pool with enhanced degradation
    init_resource_pool "$MAX_PARALLEL" "$current_memory_mb" "$current_cores"
    local adjusted_parallel=$(apply_enhanced_degradation "$MAX_PARALLEL")

    echo "⚡ Parallel builds enabled (max: $adjusted_parallel concurrent, via GNU parallel)"
    get_resource_stats
    echo ""

    # Initialize progress tracking
    init_progress_tracking "$total_archs" "$VERSION" "$PACKAGE_NAME" 2>/dev/null || true

    # Export all variables needed by worker subprocesses spawned by GNU parallel.
    # GNU parallel forks fresh bash processes that do not inherit shell variables,
    # only exported environment variables.
    export SCRIPT_DIR PACKAGE_NAME VERSION BUILD_VERSION GITHUB_REPO
    export MAX_PARALLEL LINTIAN_CHECK TELEMETRY_ENABLED SAVE_BASELINE
    export ARCH CONFIG_FILE ACTION_PATH
    # Telemetry state (may be unset if telemetry is disabled — that is fine)
    export BUILD_START_TIME TELEMETRY_DIR 2>/dev/null || true

    # Run builds via GNU parallel. Each worker re-sources the library stack
    # through the lazy-loader, then sources orchestration.sh to get
    # build_architecture_parallel, and calls it with the architecture name.
    # --halt never  : don't cancel remaining jobs on failure (we check status files)
    # --line-buffer : flush each output line immediately for CI log readability
    parallel --jobs "$adjusted_parallel" \
             --halt never \
             --line-buffer \
             bash -c 'source "$SCRIPT_DIR/lib/lazy-loading.sh" && \
                      source "$SCRIPT_DIR/lib/orchestration.sh" && \
                      build_architecture_parallel "$1"' _ {} \
             ::: "${arch_array[@]}"

    # Check for any failures and provide detailed summary
    local failed=false
    local failed_archs=()

    for arch in "${arch_array[@]}"; do
        if [ -f "build_${arch}.status" ]; then
            local status
            status=$(cat "build_${arch}.status")
            if [ "$status" = "FAILED" ]; then
                failed=true
                failed_archs+=("$arch")
                # Print build log for failed arch before cleanup
                if [ -f "build_${arch}.log" ]; then
                    echo ""
                    echo "   📋 Error log for $arch:"
                    head -30 "build_${arch}.log"
                    echo "   ---"
                fi
            fi
            rm -f "build_${arch}.status" "build_${arch}.log" "build_${arch}.time"
        fi
    done

    # Cleanup progress tracking
    cleanup_progress_tracking 2>/dev/null || true

    if [ "$failed" = "true" ]; then
        echo ""
        echo "=========================================="
        echo "❌ Build Summary: ${#failed_archs[@]} failed, $((total_archs - ${#failed_archs[@]})) succeeded"
        echo "=========================================="
        echo ""
        echo "Failed architectures:"
        for arch in "${failed_archs[@]}"; do
            echo "  • $arch"
        done
        echo ""
        cleanup_api_cache
        cleanup_resource_pool
        exit 1
    fi
}
