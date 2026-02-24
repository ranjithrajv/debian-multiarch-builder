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

    echo "⚡ Parallel builds enabled (max: $adjusted_parallel concurrent, enhanced resource pooling)"
    get_resource_stats
    echo ""

    # Initialize progress tracking
    init_progress_tracking "$total_archs" "$VERSION" "$PACKAGE_NAME" 2>/dev/null || true

    # Use job control for more efficient process management
    local arch_index=0
    local completed_count=0

    # Enable job control
    set -m

    # Function to get currently running jobs
    get_running_jobs() {
        jobs -r | wc -l
    }

    # Function to start next available build with resource pooling
    start_next_build() {
        if [ $arch_index -lt $total_archs ]; then
            local next_arch="${arch_array[$arch_index]}"

            # Try to acquire resources for this build
            local job_id="build_${next_arch}_$$"
            local resource_result
            resource_result=$(acquire_resources "$job_id" 1024 1 2>/dev/null || echo "FAILED")

            if [[ "$resource_result" == "FAILED"* ]]; then
                # Insufficient resources, skip for now
                return 1
            fi

            echo "🔨 Starting build for $next_arch ($((arch_index+1))/$total_archs)..."
            
            # Update progress tracking
            update_arch_status "$next_arch" "running" "Build started" 2>/dev/null || true

            # Start build with resource tracking
            build_architecture_parallel "$next_arch" "$job_id" &
            local build_pid=$!

            # Start resource monitoring
            local monitor_pid=$(monitor_job_resources "$job_id" "$build_pid")

            # Store job and monitor PIDs for cleanup
            echo "${build_pid}:${monitor_pid}" > "${RESOURCE_POOL_STATE_DIR}/job_${job_id}_pids"

            arch_index=$((arch_index + 1))

            # Show current resource status
            local availability=$(get_resource_availability)
            local avail_mem=$(echo "$availability" | cut -d: -f1)
            local avail_cores=$(echo "$availability" | cut -d: -f2)
            local avail_jobs=$(echo "$availability" | cut -d: -f3)

            echo "   ⚡ Resources: ${avail_mem}MB RAM, ${avail_cores} cores, ${avail_jobs} slots available"
            
            # Display progress dashboard if terminal supports it
            if [ -t 1 ]; then
                display_progress_dashboard 2>/dev/null || true
            fi
        fi
    }

    # Start initial batch of builds
    while [ $(get_running_jobs) -lt $adjusted_parallel ] && [ $arch_index -lt $total_archs ]; do
        start_next_build
    done

    # Main build loop with optimized polling
    while [ $arch_index -lt $total_archs ] || [ $(get_running_jobs) -gt 0 ]; do
        # Wait for any job to complete with timeout
        local wait_result=0
        if [ $(get_running_jobs) -gt 0 ]; then
            # Use wait -n to wait for next job completion (bash 5.x on GitHub Actions runners)
            wait -n || wait_result=$?
        fi
        
        # Process completed jobs
        for job in $(jobs -p); do
            if ! kill -0 $job 2>/dev/null; then
                # Job completed, get exit code
                set +e
                wait $job
                local exit_code=$?
                set -e
                
                # Find the architecture and job_id for this completed job
                local arch=""
                local job_id=""
                for status_file in build_*.status; do
                    if [ -f "$status_file" ]; then
                        local test_arch=$(basename "$status_file" .status | sed 's/build_//')
                        if [ -n "$test_arch" ]; then
                            # Find corresponding job_id
                            for pid_file in "${RESOURCE_POOL_STATE_DIR}"/job_build_*_pids; do
                                if [ -f "$pid_file" ]; then
                                    local pid_file_arch=$(basename "$pid_file" | sed -E 's/job_build_(.+)_([0-9]+)_pids/\1/')
                                    if [ "$pid_file_arch" = "$test_arch" ]; then
                                        arch="$test_arch"
                                        job_id=$(basename "$pid_file" | sed 's/_pids//')
                                        break
                                    fi
                                fi
                            done
                            if [ -n "$arch" ]; then
                                break
                            fi
                        fi
                    fi
                done
                
                if [ -n "$arch" ]; then
                    # Read duration if available
                    local duration_str=""
                    if [ -f "build_${arch}.time" ]; then
                        local duration=$(cat "build_${arch}.time")
                        duration_str=" ($(format_duration $duration))"
                    fi

                    completed_count=$((completed_count + 1))

                    if [ $exit_code -eq 0 ]; then
                        echo "✅ Completed build for $arch$duration_str [$completed_count/$total_archs]"
                        # Update progress tracking
                        update_arch_status "$arch" "completed" "Success${duration_str}" 2>/dev/null || true
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
                        # Update progress tracking
                        update_arch_status "$arch" "failed" "Build failed${duration_str}" 2>/dev/null || true
                    fi

                    # Release resources and cleanup
                    if [ -n "$job_id" ]; then
                        release_resources "$job_id"

                        # Kill monitor process if still running
                        if [ -f "${RESOURCE_POOL_STATE_DIR}/${job_id}_pids" ]; then
                            local pids=$(cat "${RESOURCE_POOL_STATE_DIR}/${job_id}_pids")
                            local monitor_pid=$(echo "$pids" | cut -d: -f2)
                            if [ -n "$monitor_pid" ] && kill -0 "$monitor_pid" 2>/dev/null; then
                                kill "$monitor_pid" 2>/dev/null || true
                            fi
                            rm -f "${RESOURCE_POOL_STATE_DIR}/${job_id}_pids"
                        fi
                    fi
                    
                    # Display updated progress
                    if [ -t 1 ]; then
                        display_progress_dashboard 2>/dev/null || true
                    fi
                fi
                
                # Start next build if available
                start_next_build
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
