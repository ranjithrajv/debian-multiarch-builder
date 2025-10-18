#!/bin/bash

# Enhanced Build Telemetry and Metrics Collection
# Provides comprehensive build monitoring and performance analysis

# Global telemetry configuration
TELEMETRY_DIR=".telemetry"
TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-true}"
TELEMETRY_LOG_FILE="$TELEMETRY_DIR/build-telemetry.log"
TELEMETRY_DATA_FILE="$TELEMETRY_DIR/metrics.json"
BASELINE_DATA_FILE="$TELEMETRY_DIR/baseline.json"

# Telemetry state variables
BUILD_START_TIME=""
BUILD_END_TIME=""
PEAK_MEMORY_USAGE=0
CURRENT_MEMORY_USAGE=0
NETWORK_BYTES_DOWNLOADED=0
NETWORK_BYTES_UPLOADED=0
BUILD_FAILURE_CATEGORY=""
PERFORMANCE_REGRESSIONS=()

# Network tracking
NETWORK_INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}' || echo "eth0")

# Initialize telemetry system
init_telemetry() {
    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    mkdir -p "$TELEMETRY_DIR"

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

    BUILD_START_TIME=$(date +%s)
    start_memory_monitoring
    start_network_monitoring

    # Collect Docker and system information for failure diagnosis
    collect_docker_info
    collect_system_resources

    info "Telemetry system initialized with Docker and system info"
}

# Memory usage monitoring
start_memory_monitoring() {
    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    # Monitor memory in background
    {
        while [ -f "$TELEMETRY_DIR/monitoring.active" ]; do
            local mem_usage=$(get_current_memory_usage)
            local timestamp=$(date +%s)

            # Update peak memory
            if [ "$mem_usage" -gt "$PEAK_MEMORY_USAGE" ]; then
                PEAK_MEMORY_USAGE=$mem_usage
            fi

            # Log memory sample
            echo "{\"timestamp\": $timestamp, \"memory_mb\": $mem_usage}" >> "$TELEMETRY_DIR/memory-samples.log"

            sleep 5  # Sample every 5 seconds
        done
    } &

    # Create monitoring flag
    touch "$TELEMETRY_DIR/monitoring.active"
    echo $! > "$TELEMETRY_DIR/memory-monitor.pid"
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

# Network usage monitoring
start_network_monitoring() {
    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    # Get initial network stats
    local initial_stats=$(get_network_stats)
    echo "$initial_stats" > "$TELEMETRY_DIR/network-initial.log"

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
    if command -v ip >/dev/null 2>&1; then
        # Use ip command
        ip -s link show "$NETWORK_INTERFACE" 2>/dev/null | awk '/RX:/{getline; rx=$2} /TX:/{getline; tx=$2} END{print rx, tx}'
    elif [ -f "/proc/net/dev" ]; then
        # Use /proc/net/dev
        awk -v iface="$NETWORK_INTERFACE" '$1 ~ iface {print $2, $10}' /proc/net/dev
    else
        echo "0 0"
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

    if command -v yq >/dev/null 2>&1; then
        yq eval ".build_session.start_time = $(date -d "@$BUILD_START_TIME" -Iseconds)" -i "$TELEMETRY_DATA_FILE"
        yq eval ".build_session.end_time = $(date -d "@$BUILD_END_TIME" -Iseconds)" -i "$TELEMETRY_DATA_FILE"
        yq eval ".build_session.duration_seconds = $build_duration" -i "$TELEMETRY_DATA_FILE"
        yq eval ".memory_metrics.peak_usage_mb = $PEAK_MEMORY_USAGE" -i "$TELEMETRY_DATA_FILE"
        yq eval ".network_metrics.bytes_downloaded = $NETWORK_BYTES_DOWNLOADED" -i "$TELEMETRY_DATA_FILE"
        yq eval ".network_metrics.bytes_uploaded = $NETWORK_BYTES_UPLOADED" -i "$TELEMETRY_DATA_FILE"
    fi
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