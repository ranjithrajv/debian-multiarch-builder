#!/bin/bash

# Enhanced Build Telemetry and Metrics Collection
# Provides comprehensive build monitoring and performance analysis

# Global telemetry configuration
TELEMETRY_DIR=".telemetry"
TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-true}"
TELEMETRY_LOG_FILE="$TELEMETRY_DIR/build-telemetry.log"
TELEMETRY_DATA_FILE="$TELEMETRY_DIR/metrics.json"
BASELINE_DATA_FILE="$TELEMETRY_DIR/baseline.json"

# Telemetry state variables (BUILD_START_TIME and BUILD_END_TIME are set in main script)
export BUILD_START_TIME=""
export BUILD_END_TIME=""
export PEAK_MEMORY_USAGE=0
export PEAK_CPU_USAGE=0
export CURRENT_MEMORY_USAGE=0
export CURRENT_CPU_USAGE=0
export NETWORK_BYTES_DOWNLOADED=0
export NETWORK_BYTES_UPLOADED=0
export BUILD_FAILURE_CATEGORY=""
export PERFORMANCE_REGRESSIONS=()

# Network tracking
export NETWORK_INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}' || echo "eth0")

# Initialize telemetry system
init_telemetry() {
    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        echo "Telemetry disabled"
        return 0
    fi

    mkdir -p "$TELEMETRY_DIR"
    echo "Telemetry initialized: TELEMETRY_ENABLED=$TELEMETRY_ENABLED, TELEMETRY_DIR=$TELEMETRY_DIR"
    echo "Network interface: $NETWORK_INTERFACE"

    # Initialize telemetry log
    {
        echo "=== Build Telemetry Session ==="
        echo "Timestamp: $(date -Iseconds)"
        echo "Hostname: $(hostname)"
        echo "OS Info: $(uname -a)"
        echo "CPU Info: $(nproc) cores"
        echo "Memory Total: $(free -h | awk '/^Mem:/ {print $2}')"
        echo "Disk Space: $(df -h . | tail -1 | awk '{print $4}') available"
        echo "==============================="
    } >> "$TELEMETRY_LOG_FILE"

    # Initialize metrics JSON structure
    cat > "$TELEMETRY_DATA_FILE" << EOF
{
  "build_session": {
    "start_time": "",
    "end_time": "",
    "duration_seconds": 0,
    "hostname": "$(hostname)",
    "os_info": "$(uname -a)",
    "cpu_cores": $(nproc),
    "memory_total_mb": $(free -m | awk '/^Mem:/ {print $2}'),
    "disk_available_gb": $(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
  },
  "memory_metrics": {
    "peak_usage_mb": 0,
    "average_usage_mb": 0,
    "samples": []
  },
  "cpu_metrics": {
    "peak_usage_percent": 0,
    "average_usage_percent": 0,
    "total_samples": 0,
    "samples": []
  },
  "network_metrics": {
    "bytes_downloaded": 0,
    "bytes_uploaded": 0,
    "interface": "$NETWORK_INTERFACE",
    "connection_count": 0
  },
  "build_metrics": {
    "failure_category": "",
    "failure_stage": "",
    "failure_reason": "",
    "failure_details": [],
    "failure_code": 0,
    "packages_built": 0,
    "packages_failed": 0,
    "build_stages": [],
    "docker_info": {
      "version": "",
      "daemon_running": false,
      "available_images": 0
    },
    "system_resources": {
      "disk_space_before_gb": 0,
      "disk_space_after_gb": 0,
      "memory_available_mb": 0
    }
  },
  "performance_metrics": {
    "regressions_detected": [],
    "baseline_comparison": {},
    "performance_score": 0
  }
}
EOF

    # Use BUILD_START_TIME from main script
    if [ -z "$BUILD_START_TIME" ] || [ "$BUILD_START_TIME" = "0" ]; then
        BUILD_START_TIME=$(date +%s)
    fi

    start_resource_monitoring
    start_network_monitoring

    # Collect Docker and system information for failure diagnosis
    collect_docker_info
    collect_system_resources

    info "Telemetry system initialized with Docker and system info"
}

# Resource usage monitoring (CPU + Memory)
start_resource_monitoring() {
    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    echo "Starting resource monitoring (CPU + Memory)..."

    # Monitor resources in background with exported variables
    {
        echo "Resource monitor started: $$" >> "$TELEMETRY_DIR/resource-monitor.log"

        # Initialize tracking variables
        local cpu_total=0
        local cpu_samples=0
        local peak_cpu=0

        while [ -f "$TELEMETRY_DIR/monitoring.active" ]; do
            local timestamp=$(date +%s)
            local mem_usage=$(get_current_memory_usage)
            local cpu_usage=$(get_current_cpu_usage)

            # Update peak memory
            current_peak_mem=$(cat "$TELEMETRY_DIR/current-peak-memory.txt" 2>/dev/null || echo "0")
            if [ "$mem_usage" -gt "$current_peak_mem" ]; then
                echo "$mem_usage" > "$TELEMETRY_DIR/current-peak-memory.txt"
            fi

            # Update peak CPU
            if [ "$cpu_usage" -gt "$peak_cpu" ]; then
                peak_cpu=$cpu_usage
                echo "$peak_cpu" > "$TELEMETRY_DIR/current-peak-cpu.txt"
            fi

            # Track CPU samples for averaging
            cpu_total=$((cpu_total + cpu_usage))
            cpu_samples=$((cpu_samples + 1))

            # Log resource sample
            echo "{\"timestamp\": $timestamp, \"memory_mb\": $mem_usage, \"cpu_percent\": $cpu_usage, \"cpu_avg_percent\": $((cpu_total / cpu_samples))}" >> "$TELEMETRY_DIR/resource-samples.log"

            # Update exported peak values
            PEAK_MEMORY_USAGE=$mem_usage
            PEAK_CPU_USAGE=$peak_cpu

            sleep 3  # Sample every 3 seconds for more detailed monitoring
        done
        echo "Resource monitor stopped" >> "$TELEMETRY_DIR/resource-monitor.log"
    } &

    # Create monitoring flag
    touch "$TELEMETRY_DIR/monitoring.active"
    echo $! > "$TELEMETRY_DIR/resource-monitor.pid"
    echo "0" > "$TELEMETRY_DIR/current-peak-memory.txt"
    echo "0" > "$TELEMETRY_DIR/current-peak-cpu.txt"
    echo "Resource monitoring started with PID: $!"
}

# Legacy memory monitoring function (kept for compatibility)
start_memory_monitoring() {
    start_resource_monitoring
}

# Get current memory usage in MB
get_current_memory_usage() {
    # Get memory usage of current process and children
    local pid=$$
    local total_mem=0

    # Get memory for current process tree
    while [ "$pid" -gt 1 ]; do
        local mem_kb=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print $1}' || echo 0)
        total_mem=$((total_mem + mem_kb))
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | awk '{print $1}' || echo 1)
    done

    echo $((total_mem / 1024))  # Convert KB to MB
}

# Get current CPU usage percentage
get_current_cpu_usage() {
    # Get CPU usage for current process and system
    local current_pid=$$

    # Get system CPU stats (total cpu time)
    local cpu_line=$(grep '^cpu ' /proc/stat)
    local cpu_idle=$(echo "$cpu_line" | awk '{print $5}')
    local cpu_total=$(echo "$cpu_line" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')

    # Wait a short time and get new stats
    sleep 0.1
    local new_cpu_line=$(grep '^cpu ' /proc/stat)
    local new_cpu_idle=$(echo "$new_cpu_line" | awk '{print $5}')
    local new_cpu_total=$(echo "$new_cpu_line" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')

    # Calculate CPU usage percentage
    local cpu_diff=$((new_cpu_total - cpu_total))
    local idle_diff=$((new_cpu_idle - cpu_idle))

    if [ "$cpu_diff" -gt 0 ]; then
        local cpu_usage=$((100 * (cpu_diff - idle_diff) / cpu_diff))
        # Cap at 100%
        if [ "$cpu_usage" -gt 100 ]; then
            cpu_usage=100
        fi
        echo "$cpu_usage"
    else
        echo "0"
    fi
}

# Network usage monitoring
start_network_monitoring() {
    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    echo "Starting network monitoring on interface: $NETWORK_INTERFACE"

    # Get initial network stats
    local initial_stats=$(get_network_stats)
    echo "$initial_stats" > "$TELEMETRY_DIR/network-initial.log"
    echo "Initial network stats: $initial_stats" >> "$TELEMETRY_DIR/network-monitor.log"

    # Monitor network in background
    {
        while [ -f "$TELEMETRY_DIR/monitoring.active" ]; do
            local current_stats=$(get_network_stats)
            local timestamp=$(date +%s)

            # Calculate deltas
            local rx_bytes=$(echo "$current_stats" | awk '{print $1}')
            local tx_bytes=$(echo "$current_stats" | awk '{print $2}')
            local initial_rx=$(echo "$initial_stats" | awk '{print $1}')
            local initial_tx=$(echo "$initial_stats" | awk '{print $2}')

            local delta_rx=$((rx_bytes - initial_rx))
            local delta_tx=$((tx_bytes - initial_tx))

            echo "{\"timestamp\": $timestamp, \"rx_bytes\": $delta_rx, \"tx_bytes\": $delta_tx}" >> "$TELEMETRY_DIR/network-samples.log"

            sleep 10  # Sample every 10 seconds
        done
    } &

    echo $! > "$TELEMETRY_DIR/network-monitor.pid"
}

# Get network statistics
get_network_stats() {
    # Try multiple methods to get network stats
    local stats=""

    if command -v ip >/dev/null 2>&1; then
        # Use ip command
        stats=$(ip -s link show "$NETWORK_INTERFACE" 2>/dev/null | awk '/RX:/{getline; rx=$2} /TX:/{getline; tx=$2} END{print rx, tx}')
    fi

    if [ -z "$stats" ] && [ -f "/proc/net/dev" ]; then
        # Use /proc/net/dev as fallback
        stats=$(awk -v iface="$NETWORK_INTERFACE" '$1 ~ iface {print $2, $10}' /proc/net/dev)
    fi

    if [ -z "$stats" ]; then
        echo "0 0"
    else
        echo "$stats"
    fi
}

# Record build stage start
record_build_stage() {
    local stage_name="$1"
    local stage_start=$(date +%s)

    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    echo "{\"stage\": \"$stage_name\", \"start_time\": $stage_start, \"status\": \"started\"}" >> "$TELEMETRY_DIR/build-stages.log"
    info "Telemetry: Started stage - $stage_name"
}

# Record build stage completion
record_build_stage_complete() {
    local stage_name="$1"
    local stage_status="$2"  # success, failure, warning
    local stage_message="$3"
    local stage_end=$(date +%s)

    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    echo "{\"stage\": \"$stage_name\", \"end_time\": $stage_end, \"status\": \"$stage_status\", \"message\": \"$stage_message\"}" >> "$TELEMETRY_DIR/build-stages.log"

    # Record in main telemetry
    update_telemetry_field "build_metrics.build_stages" "{\"name\": \"$stage_name\", \"status\": \"$stage_status\", \"duration\": 0}"

    info "Telemetry: Completed stage - $stage_name ($stage_status)"
}

# Record build failure with categorization
record_build_failure() {
    local failure_stage="$1"
    local failure_reason="$2"
    local error_code="$3"

    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    BUILD_FAILURE_CATEGORY=$(categorize_failure "$failure_stage" "$failure_reason" "$error_code")

    # Update telemetry
    update_telemetry_field "build_metrics.failure_category" "$BUILD_FAILURE_CATEGORY"
    update_telemetry_field "build_metrics.failure_stage" "$failure_stage"
    update_telemetry_field "build_metrics.failure_reason" "$failure_reason"
    update_telemetry_field "build_metrics.failure_code" "$error_code"

    warning "Telemetry: Build failure categorized as $BUILD_FAILURE_CATEGORY"
}

# Categorize build failures
categorize_failure() {
    local stage="$1"
    local reason="$2"
    local code="$3"

    # Docker-specific failures
    if [ "$stage" = "docker_build" ]; then
        if echo "$reason" | grep -qi -E "(no such file|not found|file.*missing|command.*not found)"; then
            echo "docker_missing_files"
        elif echo "$reason" | grep -qi -E "(permission|denied|access|cannot.*open)"; then
            echo "docker_permission"
        elif echo "$reason" | grep -qi -E "(memory|disk|space|resource|no space left)"; then
            echo "docker_resource"
        elif echo "$reason" | grep -qi -E "(network|connection|timeout|download|pull)"; then
            echo "docker_network"
        elif echo "$reason" | grep -qi -E "(dockerfile|syntax|invalid)"; then
            echo "dockerfile_syntax"
        else
            echo "docker_general"
        fi
    # Network-related failures
    elif echo "$reason" | grep -qi -E "(connection|timeout|network|download|curl|wget|404|not found)"; then
        echo "network"
    # Dependency-related failures
    elif echo "$reason" | grep -qi -E "(dependency|apt|dpkg|install|package.*not found)"; then
        echo "dependency"
    # Architecture-related failures
    elif echo "$reason" | grep -qi -E "(architecture|cross|qemu|multiarch|unsupported)"; then
        echo "architecture"
    # Build-related failures
    elif echo "$reason" | grep -qi -E "(compile|build|make|cmake|error.*\d+:|gcc|clang)"; then
        echo "compilation"
    # Package-related failures
    elif echo "$reason" | grep -qi -E "(package|deb|lintian|debian|dpkg-deb)"; then
        echo "packaging"
    # Configuration-related failures
    elif echo "$reason" | grep -qi -E "(config|yaml|setting|parameter|invalid.*argument)"; then
        echo "configuration"
    # Permission-related failures
    elif echo "$reason" | grep -qi -E "(permission|denied|access|auth|cannot.*create)"; then
        echo "permission"
    # Resource-related failures
    elif echo "$reason" | grep -qi -E "(memory|disk|space|resource|out of memory|oom)"; then
        echo "resource"
    # Checksum/security failures
    elif echo "$reason" | grep -qi -E "(checksum|hash|security|verify|gpg|signature)"; then
        echo "security"
    else
        echo "unknown"
    fi
}

# Finalize telemetry collection
finalize_telemetry() {
    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    echo "Finalizing telemetry collection..."
    BUILD_END_TIME=$(date +%s)

    # Stop monitoring
    if [ -f "$TELEMETRY_DIR/monitoring.active" ]; then
        rm -f "$TELEMETRY_DIR/monitoring.active"
    fi

    # Kill monitoring processes
    if [ -f "$TELEMETRY_DIR/memory-monitor.pid" ]; then
        kill $(cat "$TELEMETRY_DIR/memory-monitor.pid") 2>/dev/null || true
        rm -f "$TELEMETRY_DIR/memory-monitor.pid"
    fi

    if [ -f "$TELEMETRY_DIR/network-monitor.pid" ]; then
        kill $(cat "$TELEMETRY_DIR/network-monitor.pid") 2>/dev/null || true
        rm -f "$TELEMETRY_DIR/network-monitor.pid"
    fi

    # Calculate final network stats
    local final_network=$(get_network_stats)
    if [ -f "$TELEMETRY_DIR/network-initial.log" ]; then
        local initial_network=$(cat "$TELEMETRY_DIR/network-initial.log")
        local initial_rx=$(echo "$initial_network" | awk '{print $1}')
        local initial_tx=$(echo "$initial_network" | awk '{print $2}')
        local final_rx=$(echo "$final_network" | awk '{print $1}')
        local final_tx=$(echo "$final_network" | awk '{print $2}')

        NETWORK_BYTES_DOWNLOADED=$((final_rx - initial_rx))
        NETWORK_BYTES_UPLOADED=$((final_tx - initial_tx))
    fi

    # Update final system resources
    update_final_system_resources

    # Update final telemetry data
    update_final_telemetry_data

    # Check for performance regressions
    check_performance_regressions

    # Generate telemetry summary
    generate_telemetry_summary

    info "Telemetry collection completed"
}

# Update telemetry field in JSON
update_telemetry_field() {
    local field_path="$1"
    local field_value="$2"

    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    # Use yq to update the field
    if command -v yq >/dev/null 2>&1; then
        yq eval ".$field_path = $field_value" -i "$TELEMETRY_DATA_FILE" 2>/dev/null || true
    fi
}

# Update final telemetry data
update_final_telemetry_data() {
    local build_duration=$((BUILD_END_TIME - BUILD_START_TIME))

    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    # Debug: Log key values
    echo "DEBUG: BUILD_START_TIME=$BUILD_START_TIME, BUILD_END_TIME=$BUILD_END_TIME, duration=$build_duration" >> "$TELEMETRY_DIR/debug.log"

    # Read peak memory and CPU from files to get latest values
    if [ -f "$TELEMETRY_DIR/current-peak-memory.txt" ]; then
        PEAK_MEMORY_USAGE=$(cat "$TELEMETRY_DIR/current-peak-memory.txt")
        echo "DEBUG: PEAK_MEMORY_USAGE=$PEAK_MEMORY_USAGE" >> "$TELEMETRY_DIR/debug.log"
    else
        echo "DEBUG: No peak memory file found" >> "$TELEMETRY_DIR/debug.log"
    fi

    if [ -f "$TELEMETRY_DIR/current-peak-cpu.txt" ]; then
        PEAK_CPU_USAGE=$(cat "$TELEMETRY_DIR/current-peak-cpu.txt")
        echo "DEBUG: PEAK_CPU_USAGE=$PEAK_CPU_USAGE" >> "$TELEMETRY_DIR/debug.log"
    else
        echo "DEBUG: No peak CPU file found" >> "$TELEMETRY_DIR/debug.log"
    fi

    echo "DEBUG: NETWORK_BYTES_DOWNLOADED=$NETWORK_BYTES_DOWNLOADED, NETWORK_BYTES_UPLOADED=$NETWORK_BYTES_UPLOADED" >> "$TELEMETRY_DIR/debug.log"

    # Also output debug info to main log for visibility
    echo "🔍 TELEMETRY DEBUG: Duration=${build_duration}s, Memory=${PEAK_MEMORY_USAGE}MB, CPU=${PEAK_CPU_USAGE}%, Down=${NETWORK_BYTES_DOWNLOADED}, Up=${NETWORK_BYTES_UPLOADED}"

    echo "🔍 TELEMETRY: Starting yq updates..."
    if command -v yq >/dev/null 2>&1; then
        echo "🔍 TELEMETRY: yq command found"
        # Use proper quoting for date values to avoid yq parsing issues
        local start_time_iso=$(date -d "@$BUILD_START_TIME" -Iseconds)
        local end_time_iso=$(date -d "@$BUILD_END_TIME" -Iseconds)

        echo "DEBUG: yq available, updating telemetry file: $TELEMETRY_DATA_FILE" >> "$TELEMETRY_DIR/debug.log"

        # Update telemetry with better error handling and logging
        if yq eval ".build_session.start_time = \"$start_time_iso\"" -i "$TELEMETRY_DATA_FILE" 2>> "$TELEMETRY_DIR/debug.log"; then
            echo "DEBUG: Updated start_time successfully" >> "$TELEMETRY_DIR/debug.log"
        else
            echo "ERROR: Failed to update start_time" >> "$TELEMETRY_DIR/debug.log"
        fi

        if yq eval ".build_session.end_time = \"$end_time_iso\"" -i "$TELEMETRY_DATA_FILE" 2>> "$TELEMETRY_DIR/debug.log"; then
            echo "DEBUG: Updated end_time successfully" >> "$TELEMETRY_DIR/debug.log"
        else
            echo "ERROR: Failed to update end_time" >> "$TELEMETRY_DIR/debug.log"
        fi

        if yq eval ".build_session.duration_seconds = $build_duration" -i "$TELEMETRY_DATA_FILE" 2>> "$TELEMETRY_DIR/debug.log"; then
            echo "DEBUG: Updated duration successfully: $build_duration" >> "$TELEMETRY_DIR/debug.log"
        else
            echo "ERROR: Failed to update duration: $build_duration" >> "$TELEMETRY_DIR/debug.log"
        fi

        if yq eval ".memory_metrics.peak_usage_mb = $PEAK_MEMORY_USAGE" -i "$TELEMETRY_DATA_FILE" 2>> "$TELEMETRY_DIR/debug.log"; then
            echo "DEBUG: Updated memory successfully: $PEAK_MEMORY_USAGE" >> "$TELEMETRY_DIR/debug.log"
        else
            echo "ERROR: Failed to update memory: $PEAK_MEMORY_USAGE" >> "$TELEMETRY_DIR/debug.log"
        fi

        if yq eval ".cpu_metrics.peak_usage_percent = $PEAK_CPU_USAGE" -i "$TELEMETRY_DATA_FILE" 2>> "$TELEMETRY_DIR/debug.log"; then
            echo "DEBUG: Updated CPU successfully: $PEAK_CPU_USAGE" >> "$TELEMETRY_DIR/debug.log"
        else
            echo "ERROR: Failed to update CPU: $PEAK_CPU_USAGE" >> "$TELEMETRY_DIR/debug.log"
        fi

        if yq eval ".network_metrics.bytes_downloaded = $NETWORK_BYTES_DOWNLOADED" -i "$TELEMETRY_DATA_FILE" 2>> "$TELEMETRY_DIR/debug.log"; then
            echo "DEBUG: Updated download bytes successfully: $NETWORK_BYTES_DOWNLOADED" >> "$TELEMETRY_DIR/debug.log"
        else
            echo "ERROR: Failed to update download bytes: $NETWORK_BYTES_DOWNLOADED" >> "$TELEMETRY_DIR/debug.log"
        fi

        if yq eval ".network_metrics.bytes_uploaded = $NETWORK_BYTES_UPLOADED" -i "$TELEMETRY_DATA_FILE" 2>> "$TELEMETRY_DIR/debug.log"; then
            echo "DEBUG: Updated upload bytes successfully: $NETWORK_BYTES_UPLOADED" >> "$TELEMETRY_DIR/debug.log"
        else
            echo "ERROR: Failed to update upload bytes: $NETWORK_BYTES_UPLOADED" >> "$TELEMETRY_DIR/debug.log"
        fi
    else
        echo "ERROR: yq not available for telemetry updates" >> "$TELEMETRY_DIR/debug.log"
        echo "Warning: yq not available for telemetry updates"
    fi

    echo "🔍 TELEMETRY: Finished yq updates"
}

# Check for performance regressions
check_performance_regressions() {
    if [ "$TELEMETRY_ENABLED" != "true" ] || [ ! -f "$BASELINE_DATA_FILE" ]; then
        return 0
    fi

    local current_duration=0
    local baseline_duration=0
    local current_memory=0
    local baseline_memory=0

    # Extract current metrics
    if command -v jq >/dev/null 2>&1; then
        current_duration=$(jq -r '.build_session.duration_seconds // 0' "$TELEMETRY_DATA_FILE")
        current_memory=$(jq -r '.memory_metrics.peak_usage_mb // 0' "$TELEMETRY_DATA_FILE")
        baseline_duration=$(jq -r '.build_session.duration_seconds // 0' "$BASELINE_DATA_FILE")
        baseline_memory=$(jq -r '.memory_metrics.peak_usage_mb // 0' "$BASELINE_DATA_FILE")
    fi

    # Check for regressions (20% threshold)
    local duration_threshold=$((baseline_duration * 120 / 100))
    local memory_threshold=$((baseline_memory * 120 / 100))

    if [ "$current_duration" -gt "$duration_threshold" ] && [ "$baseline_duration" -gt 0 ]; then
        local regression="Build duration increased by $(( (current_duration - baseline_duration) * 100 / baseline_duration ))%"
        PERFORMANCE_REGRESSIONS+=("$regression")
        warning "Performance regression detected: $regression"
    fi

    if [ "$current_memory" -gt "$memory_threshold" ] && [ "$baseline_memory" -gt 0 ]; then
        local regression="Memory usage increased by $(( (current_memory - baseline_memory) * 100 / baseline_memory ))%"
        PERFORMANCE_REGRESSIONS+=("$regression")
        warning "Performance regression detected: $regression"
    fi

    # Update telemetry with regression data
    if [ ${#PERFORMANCE_REGRESSIONS[@]} -gt 0 ]; then
        local regressions_json=$(printf '%s\n' "${PERFORMANCE_REGRESSIONS[@]}" | jq -R . | jq -s .)
        update_telemetry_field "performance_metrics.regressions_detected" "$regressions_json"
    fi
}

# Generate telemetry summary
generate_telemetry_summary() {
    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    {
        echo ""
        echo "=== Build Telemetry Summary ==="
        echo "Build Duration: $((BUILD_END_TIME - BUILD_START_TIME)) seconds"
        echo "Peak Memory Usage: ${PEAK_MEMORY_USAGE} MB"
        echo "Network Downloaded: $(format_bytes $NETWORK_BYTES_DOWNLOADED)"
        echo "Network Uploaded: $(format_bytes $NETWORK_BYTES_UPLOADED)"

        if [ -n "$BUILD_FAILURE_CATEGORY" ]; then
            echo "Failure Category: $BUILD_FAILURE_CATEGORY"
        fi

        if [ ${#PERFORMANCE_REGRESSIONS[@]} -gt 0 ]; then
            echo "Performance Regressions:"
            printf '  - %s\n' "${PERFORMANCE_REGRESSIONS[@]}"
        fi

        echo "Detailed telemetry saved to: $TELEMETRY_DATA_FILE"
        echo "==============================="
    } >> "$TELEMETRY_LOG_FILE"
}

# Format bytes for human reading
format_bytes() {
    local bytes=$1
    local units=('B' 'KB' 'MB' 'GB' 'TB')
    local unit=0

    while [ "$bytes" -gt 1024 ] && [ $unit -lt 4 ]; do
        bytes=$((bytes / 1024))
        unit=$((unit + 1))
    done

    echo "${bytes} ${units[$unit]}"
}

# Save current build as baseline
save_as_baseline() {
    if [ "$TELEMETRY_ENABLED" != "true" ] || [ ! -f "$TELEMETRY_DATA_FILE" ]; then
        return 0
    fi

    cp "$TELEMETRY_DATA_FILE" "$BASELINE_DATA_FILE"
    info "Current build saved as performance baseline"
}

# Collect Docker information for failure diagnosis
collect_docker_info() {
    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    local docker_version=""
    local daemon_running=false
    local available_images=0

    if command -v docker >/dev/null 2>&1; then
        docker_version=$(docker --version 2>/dev/null | awk '{print $3}' | sed 's/,//' || echo "unknown")

        # Check if Docker daemon is running
        if docker info >/dev/null 2>&1; then
            daemon_running=true
            available_images=$(docker images --format "table {{.Repository}}" | grep -v "REPOSITORY" | wc -l || echo "0")
        fi
    fi

    # Update telemetry with Docker info
    update_telemetry_field "build_metrics.docker_info.version" "\"$docker_version\""
    update_telemetry_field "build_metrics.docker_info.daemon_running" "$daemon_running"
    update_telemetry_field "build_metrics.docker_info.available_images" "$available_images"
}

# Collect system resources for failure diagnosis
collect_system_resources() {
    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    local disk_space_before=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    local memory_available=$(free -m | awk '/^Mem:/ {print $7}')

    # Update telemetry with system resources
    update_telemetry_field "build_metrics.system_resources.disk_space_before_gb" "$disk_space_before"
    update_telemetry_field "build_metrics.system_resources.memory_available_mb" "$memory_available"
}

# Update final system resources after build
update_final_system_resources() {
    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    local disk_space_after=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    update_telemetry_field "build_metrics.system_resources.disk_space_after_gb" "$disk_space_after"
}

# Add failure details to telemetry
add_failure_detail() {
    local detail="$1"

    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    # Add detail to failure_details array using jq if available
    if command -v jq >/dev/null 2>&1 && [ -f "$TELEMETRY_DATA_FILE" ]; then
        local current_details=$(jq -r '.build_metrics.failure_details // []' "$TELEMETRY_DATA_FILE")
        local updated_details=$(echo "$current_details" | jq ". + [\"$detail\"]")
        update_telemetry_field "build_metrics.failure_details" "$updated_details"
    fi
}

# Get telemetry summary for build summary integration
get_telemetry_summary() {
    if [ "$TELEMETRY_ENABLED" != "true" ] || [ ! -f "$TELEMETRY_DATA_FILE" ]; then
        echo "{}"
        return 0
    fi

    # Extract key telemetry metrics
    if command -v jq >/dev/null 2>&1; then
        jq '{
            build_duration_seconds: .build_session.duration_seconds,
            peak_memory_mb: .memory_metrics.peak_usage_mb,
            peak_cpu_percent: .cpu_metrics.peak_usage_percent,
            network_downloaded_bytes: .network_metrics.bytes_downloaded,
            network_uploaded_bytes: .network_metrics.bytes_uploaded,
            failure_category: .build_metrics.failure_category,
            failure_stage: .build_metrics.failure_stage,
            failure_reason: .build_metrics.failure_reason,
            failure_details: .build_metrics.failure_details,
            failure_code: .build_metrics.failure_code,
            docker_info: .build_metrics.docker_info,
            system_resources: .build_metrics.system_resources,
            performance_regressions: .performance_metrics.regressions_detected
        }' "$TELEMETRY_DATA_FILE"
    else
        echo "{}"
    fi
}

# Export telemetry functions
export -f init_telemetry
export -f record_build_stage
export -f record_build_stage_complete
export -f record_build_failure
export -f finalize_telemetry
export -f get_telemetry_summary
export -f save_as_baseline
export -f add_failure_detail
export -f collect_docker_info
export -f collect_system_resources
export -f update_final_system_resources