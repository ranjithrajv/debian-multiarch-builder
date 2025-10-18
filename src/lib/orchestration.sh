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

    echo "⚡ Parallel builds enabled (max: $MAX_PARALLEL concurrent)"
    echo ""

    declare -a pids=()
    declare -a active_archs=()
    local arch_index=0
    local completed_count=0

    # Start initial batch of builds
    for build_arch in "${arch_array[@]}"; do
        if [ ${#pids[@]} -lt $MAX_PARALLEL ]; then
            echo "🔨 Starting build for $build_arch (${arch_index}/$total_archs)..."
            build_architecture_parallel "$build_arch" &
            pids+=($!)
            active_archs+=("$build_arch")
            arch_index=$((arch_index + 1))
        else
            break
        fi
    done

    # As builds complete, start new ones
    while [ $arch_index -lt $total_archs ] || [ ${#pids[@]} -gt 0 ]; do
        # Check for completed builds
        for i in "${!pids[@]}"; do
            pid=${pids[$i]}
            if ! kill -0 $pid 2>/dev/null; then
                # Build completed - capture exit code before it's lost
                set +e  # Temporarily disable exit-on-error
                wait $pid
                exit_code=$?
                set -e  # Re-enable exit-on-error

                arch=${active_archs[$i]}

                # Read duration if available
                local duration_str=""
                if [ -f "build_${arch}.time" ]; then
                    local duration=$(cat "build_${arch}.time")
                    duration_str=" ($(format_duration $duration))"
                fi

                completed_count=$((completed_count + 1))

                if [ $exit_code -eq 0 ]; then
                    echo "✅ Completed build for $arch$duration_str [$completed_count/$total_archs]"
                else
                    echo "⚠️  Build for $arch completed with errors$duration_str [$completed_count/$total_archs]"
                    echo "   💡 Architecture $arch will be skipped - other architectures will continue"
                    # Print log immediately to help with debugging
                    if [ -f "build_${arch}.log" ]; then
                        echo "   📋 Error details for $arch:"
                        cat "build_${arch}.log" | head -10  # Show first 10 lines of errors
                        echo "   🔍 Full log available in build_${arch}.log"
                        echo ""
                    fi
                fi

                # Remove from active arrays
                unset pids[$i]
                unset active_archs[$i]
                pids=("${pids[@]}")  # Reindex
                active_archs=("${active_archs[@]}")

                # Start next build if available
                if [ $arch_index -lt $total_archs ]; then
                    next_arch="${arch_array[$arch_index]}"
                    echo "🔨 Starting build for $next_arch ($((arch_index+1))/$total_archs)..."
                    build_architecture_parallel "$next_arch" &
                    pids+=($!)
                    active_archs+=("$next_arch")
                    arch_index=$((arch_index + 1))

                    # Show currently running builds
                    if [ ${#active_archs[@]} -gt 0 ]; then
                        echo "   ⚡ Running: ${active_archs[*]}"
                    fi
                fi

                break
            fi
        done

        sleep 1
    done

    # Check for any failures and provide detailed summary
    local failed=false
    local failed_archs=()

    for arch in "${arch_array[@]}"; do
        if [ -f "build_${arch}.status" ]; then
            status=$(cat "build_${arch}.status")
            if [ "$status" = "FAILED" ]; then
                failed=true
                failed_archs+=("$arch")
            fi
            rm -f "build_${arch}.status" "build_${arch}.log" "build_${arch}.time"
        fi
    done

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
        exit 1
    fi
}
