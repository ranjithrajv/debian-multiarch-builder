#!/bin/bash

# Build orchestration functions (parallel and sequential)

# Function to build architecture with logging to file (for parallel builds)
build_architecture_parallel() {
    # Disable exit-on-error for backgrounded function
    set +e

    echo "DEBUG: [parallel] Entered function for $1" >&2

    local build_arch=$1
    echo "DEBUG: [parallel] Set build_arch=$build_arch" >&2

    local log_file="build_${build_arch}.log"
    echo "DEBUG: [parallel] Set log_file=$log_file" >&2

    echo "DEBUG: [parallel] About to start redirected block" >&2

    # Test if we can write to log file
    if echo "Test write at $(date)" > "$log_file" 2>&1; then
        echo "DEBUG: [parallel] Successfully created/wrote to $log_file" >&2
    else
        echo "ERROR: [parallel] Failed to create/write to $log_file" >&2
        return 1
    fi

    # Redirect all output to log file
    {
        echo "DEBUG: Inside redirected block for $build_arch"
        echo "DEBUG: About to call build_architecture"

        if build_architecture "$build_arch"; then
            echo "DEBUG: build_architecture succeeded"
            echo "SUCCESS" > "build_${build_arch}.status"
        else
            echo "DEBUG: build_architecture failed with exit code $?"
            echo "FAILED" > "build_${build_arch}.status"
            return 1
        fi
    } > "$log_file" 2>&1

    local exit_code=$?
    echo "DEBUG: [parallel] Finished redirected block, exit_code=$exit_code" >&2
    echo "DEBUG: [parallel] Returning $exit_code" >&2
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
