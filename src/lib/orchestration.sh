#!/bin/bash

# Build orchestration functions (parallel and sequential)

# Function to build architecture with logging to file (for parallel builds)
build_architecture_parallel() {
    local build_arch=$1
    local log_file="build_${build_arch}.log"

    # Redirect all output to log file
    {
        if build_architecture "$build_arch"; then
            echo "SUCCESS" > "build_${build_arch}.status"
        else
            echo "FAILED" > "build_${build_arch}.status"
            return 1
        fi
    } > "$log_file" 2>&1
}

# Function to build all architectures sequentially
build_architecture_sequential() {
    local arch_array=("$@")
    local total_archs=${#arch_array[@]}
    local current=0

    echo "Building architectures sequentially..."
    echo ""

    for build_arch in "${arch_array[@]}"; do
        ((current++))
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

    # Start initial batch of builds
    for build_arch in "${arch_array[@]}"; do
        if [ ${#pids[@]} -lt $MAX_PARALLEL ]; then
            echo "🔨 Starting build for $build_arch (${arch_index}/$total_archs)..."
            build_architecture_parallel "$build_arch" &
            pids+=($!)
            active_archs+=("$build_arch")
            ((arch_index++))
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
                if [ $exit_code -eq 0 ]; then
                    echo "✅ Completed build for $arch"
                else
                    echo "❌ Failed build for $arch"
                    # Print log immediately to help with debugging
                    if [ -f "build_${arch}.log" ]; then
                        echo "==== Build log for $arch ===="
                        cat "build_${arch}.log"
                        echo "==== End of log ===="
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
                    ((arch_index++))
                fi

                break
            fi
        done

        sleep 1
    done

    # Check for any failures
    local failed=false
    for arch in "${arch_array[@]}"; do
        if [ -f "build_${arch}.status" ]; then
            status=$(cat "build_${arch}.status")
            if [ "$status" = "FAILED" ]; then
                failed=true
                echo ""
                echo "❌ Build failed for $arch. Log:"
                cat "build_${arch}.log"
            fi
            rm -f "build_${arch}.status" "build_${arch}.log"
        fi
    done

    if [ "$failed" = "true" ]; then
        echo ""
        echo "❌ Some builds failed"
        cleanup_api_cache
        exit 1
    fi
}
