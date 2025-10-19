#!/bin/bash

# Enhanced Build Telemetry and Metrics Collection
# Provides comprehensive build monitoring and performance analysis

# Source YAML utilities for loading externalized configuration
source "$SCRIPT_DIR/data/yaml-utils.sh"

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
export FAILURE_TYPE=""  # transient or permanent
export FAILURE_DETAILS=""
export FAILURE_CATEGORY_ENHANCED=""  # Enhanced category with remediation
export REMEDIATION_SUGGESTIONS=""
export DETAILED_FAILURE_REPORT=""
export RETRY_COUNT=0

# Comprehensive error context variables
export ERROR_CONTEXT=""  # Rich environmental context
export API_RESPONSE_CODES=""  # API response details
export SYSTEM_SNAPSHOT=""  # System state at failure time
export NETWORK_CONDITIONS=""  # Network status at failure
export ENVIRONMENT_DETAILS=""  # Build environment context
export DIAGNOSTIC_DATA=""  # Auto-collected diagnostic info

# State tracking variables
export BUILD_STATE_FILE="$TELEMETRY_DIR/build-state.json"
export ARCHITECTURE_STATE=""  # Track per-architecture state
export DISTRIBUTION_STATE=""  # Track per-distribution state
export COMPLETED_BUILDS=""  # Track successfully completed builds
export FAILED_BUILDS=""  # Track failed builds
export PENDING_BUILDS=""  # Track builds that need to be attempted
export SKIPPED_BUILDS=""  # Track builds that were skipped
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
    "failure_type": "",
    "failure_details_summary": "",
    "failure_category_enhanced": "",
    "remediation_suggestions": "",
    "retry_count": 0,
    "last_retry_attempt": "",
    "error_context": {},
    "api_response_codes": {},
    "system_snapshot": {},
    "network_conditions": {},
    "environment_details": {},
    "diagnostic_data": {},
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

            # Update exported peak values globally
            export PEAK_MEMORY_USAGE=$mem_usage
            export PEAK_CPU_USAGE=$peak_cpu

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
    # Get system-wide CPU usage (simplified for reliability)
    local cpu_line=$(grep '^cpu ' /proc/stat 2>/dev/null)
    if [ -z "$cpu_line" ]; then
        echo "0"
        return
    fi

    local cpu_idle=$(echo "$cpu_line" | awk '{print $5}')
    local cpu_total=$(echo "$cpu_line" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')

    # Short delay to get delta
    sleep 0.1
    local new_cpu_line=$(grep '^cpu ' /proc/stat 2>/dev/null)
    if [ -z "$new_cpu_line" ]; then
        echo "0"
        return
    fi

    local new_cpu_idle=$(echo "$new_cpu_line" | awk '{print $5}')
    local new_cpu_total=$(echo "$new_cpu_line" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')

    # Calculate CPU usage
    local cpu_diff=$((new_cpu_total - cpu_total))
    local idle_diff=$((new_cpu_idle - cpu_idle))

    if [ "$cpu_diff" -gt 0 ]; then
        local cpu_usage=$((100 * (cpu_diff - idle_diff) / cpu_diff))
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

# Record build failure with enhanced categorization and detailed reporting
record_build_failure() {
    local failure_stage="$1"
    local failure_reason="$2"
    local error_code="$3"
    local arch="${4:-unknown}"
    local dist="${5:-unknown}"

    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    # Basic categorization (existing)
    BUILD_FAILURE_CATEGORY=$(categorize_failure "$failure_stage" "$failure_reason" "$error_code")

    # Enhanced categorization with remediation
    categorize_failure_enhanced "$failure_stage" "$failure_reason" "$error_code"

    # Classify failure as transient or permanent
    classify_failure_type "$failure_stage" "$failure_reason" "$error_code"

    # Generate detailed failure report
    generate_detailed_failure_report "$failure_stage" "$failure_reason" "$error_code" "$arch" "$dist"

    # Collect comprehensive error context
    collect_error_context "$failure_stage" "$failure_reason" "$error_code" "$arch" "$dist"

    # Update telemetry with all failure information
    update_telemetry_field "build_metrics.failure_category" "$BUILD_FAILURE_CATEGORY"
    update_telemetry_field "build_metrics.failure_stage" "$failure_stage"
    update_telemetry_field "build_metrics.failure_reason" "$failure_reason"
    update_telemetry_field "build_metrics.failure_code" "$error_code"
    update_telemetry_field "build_metrics.failure_type" "$FAILURE_TYPE"
    update_telemetry_field "build_metrics.failure_details" "$FAILURE_DETAILS"
    update_telemetry_field "build_metrics.retry_count" "$RETRY_COUNT"
    update_telemetry_field "build_metrics.failure_category_enhanced" "$FAILURE_CATEGORY_ENHANCED"
    update_telemetry_field "build_metrics.remediation_suggestions" "$REMEDIATION_SUGGESTIONS"

    # Update telemetry with comprehensive error context
    update_telemetry_field "build_metrics.error_context" "$ERROR_CONTEXT"
    update_telemetry_field "build_metrics.api_response_codes" "$API_RESPONSE_CODES"
    update_telemetry_field "build_metrics.system_snapshot" "$SYSTEM_SNAPSHOT"
    update_telemetry_field "build_metrics.network_conditions" "$NETWORK_CONDITIONS"
    update_telemetry_field "build_metrics.environment_details" "$ENVIRONMENT_DETAILS"
    update_telemetry_field "build_metrics.diagnostic_data" "$DIAGNOSTIC_DATA"

    # Save detailed failure report to file
    if [ -n "$DETAILED_FAILURE_REPORT" ]; then
        echo "$DETAILED_FAILURE_REPORT" > "$TELEMETRY_DIR/failure-report.json"
        info "Detailed failure report saved to $TELEMETRY_DIR/failure-report.json"
    fi

    # Display enhanced failure information with comprehensive context
    echo ""
    echo "=========================================="
    echo "❌ COMPREHENSIVE FAILURE ANALYSIS"
    echo "=========================================="
    echo "📊 Failure Category: $FAILURE_CATEGORY_ENHANCED"
    echo "🏷️  Failure Type: $FAILURE_TYPE"
    echo "📍 Stage: $failure_stage"
    echo "🔧 Architecture: $arch, Distribution: $dist"
    echo ""

    # Show system context summary
    if [ -n "$SYSTEM_SNAPSHOT" ]; then
        echo "🖥️  SYSTEM CONTEXT:"
        local mem_usage=$(echo "$SYSTEM_SNAPSHOT" | jq -r '.memory.used_mb // "0"' 2>/dev/null || echo "0")
        local mem_total=$(echo "$SYSTEM_SNAPSHOT" | jq -r '.memory.total_mb // "0"' 2>/dev/null || echo "0")
        local disk_usage=$(echo "$SYSTEM_SNAPSHOT" | jq -r '.disk.usage_percent // "0"' 2>/dev/null || echo "0")
        local cpu_cores=$(echo "$SYSTEM_SNAPSHOT" | jq -r '.cpu.cores // "0"' 2>/dev/null || echo "0")
        echo "   Memory: ${mem_usage}/${mem_total} MB used"
        echo "   Disk: ${disk_usage}% used"
        echo "   CPU: ${cpu_cores} cores"
        echo ""
    fi

    # Show network conditions summary
    if [ -n "$NETWORK_CONDITIONS" ]; then
        echo "🌐 NETWORK CONDITIONS:"
        local interface=$(echo "$NETWORK_CONDITIONS" | jq -r '.interface // "unknown"' 2>/dev/null || echo "unknown")
        local status=$(echo "$NETWORK_CONDITIONS" | jq -r '.interface_status // "unknown"' 2>/dev/null || echo "unknown")
        echo "   Interface: $interface ($status)"
        echo ""
    fi

    # Show API status
    if [ -n "$API_RESPONSE_CODES" ]; then
        echo "📡 API STATUS:"
        local github_status=$(echo "$API_RESPONSE_CODES" | jq -r '.github_api_status // "unknown"' 2>/dev/null || echo "unknown")
        local rate_limit=$(echo "$API_RESPONSE_CODES" | jq -r '.github_rate_limit // "unknown"' 2>/dev/null || echo "unknown")
        echo "   GitHub API: $github_status (Rate limit: $rate_limit remaining)"
        echo ""
    fi

    echo "💡 REMEDIATION SUGGESTIONS:"
    echo "$REMEDIATION_SUGGESTIONS" | while IFS= read -r line; do
        echo "   $line"
    done
    echo ""
    echo "📋 Comprehensive reports available:"
    echo "   📄 Failure analysis: $TELEMETRY_DIR/failure-report.json"
    echo "   🔍 Telemetry data: $TELEMETRY_DIR/metrics.json"
    echo "   📊 System snapshot: Captured in failure report"
    echo "   🌐 Network conditions: Captured in failure report"
    echo "   📡 API response details: Captured in failure report"
    echo "=========================================="
    echo ""

    warning "Telemetry: Enhanced failure analysis completed - $FAILURE_CATEGORY_ENHANCED ($FAILURE_TYPE)"
}

# Classify failure as transient (retryable) or permanent (requires manual intervention)
classify_failure_type() {
    local stage="$1"
    local reason="$2"
    local code="$3"

    # Default retry count (could be incremented in retry logic)
    RETRY_COUNT=${RETRY_COUNT:-0}

    # Transient failures - these can be retried and may succeed
    if echo "$reason" | grep -qi -E "(timeout|timed out|connection.*refused|connection.*reset|network.*unreachable)"; then
        FAILURE_TYPE="transient"
        FAILURE_DETAILS="Network timeout - retryable"
        return 0
    elif echo "$reason" | grep -qi -E "(temporary.*failure|temporarily.*unavailable|service.*unavailable)"; then
        FAILURE_TYPE="transient"
        FAILURE_DETAILS="Service temporarily unavailable - retryable"
        return 0
    elif echo "$reason" | grep -qi -E "(rate.*limit|too.*many.*requests|429)"; then
        FAILURE_TYPE="transient"
        FAILURE_DETAILS="Rate limiting - retry after delay"
        return 0
    elif echo "$reason" | grep -qi -E "(docker.*pull.*failed|registry.*unavailable|manifest.*unknown)"; then
        FAILURE_TYPE="transient"
        FAILURE_DETAILS="Docker registry issue - retryable"
        return 0
    elif echo "$reason" | grep -qi -E "(download.*interrupted|wget.*failed|curl.*failed).*timeout"; then
        FAILURE_TYPE="transient"
        FAILURE_DETAILS="Download timeout - retryable"
        return 0
    elif echo "$reason" | grep -qi -E "(resource.*busy|device.*busy|locked)"; then
        FAILURE_TYPE="transient"
        FAILURE_DETAILS="Resource temporarily busy - retryable"
        return 0
    fi

    # Permanent failures - these require manual intervention
    if echo "$reason" | grep -qi -E "(no such file|file.*not found|directory.*not found|404|not found)"; then
        FAILURE_TYPE="permanent"
        FAILURE_DETAILS="Missing files or resources - manual intervention required"
        return 0
    elif echo "$reason" | grep -qi -E "(permission.*denied|access.*denied|unauthorized|401|403)"; then
        FAILURE_TYPE="permanent"
        FAILURE_DETAILS="Permission or authentication error - manual intervention required"
        return 0
    elif echo "$reason" | grep -qi -E "(invalid.*credential|authentication.*failed|login.*failed)"; then
        FAILURE_TYPE="permanent"
        FAILURE_DETAILS="Invalid credentials - manual intervention required"
        return 0
    elif echo "$reason" | grep -qi -E "(syntax.*error|parse.*error|invalid.*format|invalid.*yaml|invalid.*json)"; then
        FAILURE_TYPE="permanent"
        FAILURE_DETAILS="Syntax or format error - manual intervention required"
        return 0
    elif echo "$reason" | grep -qi -E "(command.*not found|executable.*not found|binary.*not found)"; then
        FAILURE_TYPE="permanent"
        FAILURE_DETAILS="Missing dependencies or tools - manual intervention required"
        return 0
    elif echo "$reason" | grep -qi -E "(dockerfile.*error|invalid.*instruction)"; then
        FAILURE_TYPE="permanent"
        FAILURE_DETAILS="Dockerfile configuration error - manual intervention required"
        return 0
    elif echo "$reason" | grep -qi -E "(architecture.*not.*supported|unsupported.*platform)"; then
        FAILURE_TYPE="permanent"
        FAILURE_DETAILS="Unsupported architecture or platform - manual intervention required"
        return 0
    elif echo "$reason" | grep -qi -E "(disk.*full|no.*space.*left|out.*of.*memory|oom.*killer)"; then
        FAILURE_TYPE="permanent"
        FAILURE_DETAILS="Resource exhaustion - manual intervention required"
        return 0
    elif echo "$reason" | grep -qi -E "(invalid.*config|configuration.*error|missing.*config)"; then
        FAILURE_TYPE="permanent"
        FAILURE_DETAILS="Configuration error - manual intervention required"
        return 0
    fi

    # Default classification - assume permanent for safety
    FAILURE_TYPE="permanent"
    FAILURE_DETAILS="Unknown failure type - manual investigation required"
}

# Enhanced error categorization with remediation suggestions
categorize_failure_enhanced() {
    local stage="$1"
    local reason="$2"
    local code="$3"

    # Use YAML-based failure classification
    read -r category failure_type category_enhanced remediation_suggestions < <(get_failure_classification "$reason")
    
    FAILURE_CATEGORY_ENHANCED="$category_enhanced"
    REMEDIATION_SUGGESTIONS="$remediation_suggestions"
    
    # If no match found in YAML, use default
    if [ "$FAILURE_CATEGORY_ENHANCED" = "unknown_error" ]; then
        REMEDIATION_SUGGESTIONS="1. Check complete build logs
2. Reproduce error locally
3. Search for similar issues online
4. Check upstream documentation
5. Report bug with full logs"
    fi
}

# Generate detailed failure report
generate_detailed_failure_report() {
    local stage="$1"
    local reason="$2"
    local code="$3"
    local arch="$4"
    local dist="$5"

    # Get current timestamp
    local timestamp=$(date -Iseconds)

    # Get system information
    local hostname=$(hostname)
    local os_info=$(uname -a)
    local disk_space=$(df -h . | tail -1 | awk '{print $4}')
    local memory_info=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')

    # Get Docker info if available
    local docker_version="N/A"
    local docker_images="N/A"
    if command -v docker >/dev/null 2>&1; then
        docker_version=$(docker --version 2>/dev/null || echo "Error")
        docker_images=$(docker images 2>/dev/null | wc -l || echo "Error")
    fi

    # Generate comprehensive report with full context
    DETAILED_FAILURE_REPORT="{
  \"timestamp\": \"$timestamp\",
  \"failure_summary\": {
    \"stage\": \"$stage\",
    \"reason\": \"$reason\",
    \"exit_code\": $code,
    \"failure_type\": \"$FAILURE_TYPE\",
    \"failure_category\": \"$FAILURE_CATEGORY_ENHANCED\",
    \"architecture\": \"$arch\",
    \"distribution\": \"$dist\"
  },
  \"error_context\": $ERROR_CONTEXT,
  \"api_response_codes\": $API_RESPONSE_CODES,
  \"system_snapshot\": $SYSTEM_SNAPSHOT,
  \"network_conditions\": $NETWORK_CONDITIONS,
  \"environment_details\": $ENVIRONMENT_DETAILS,
  \"diagnostic_data\": $DIAGNOSTIC_DATA,
  \"system_context\": {
    \"hostname\": \"$hostname\",
    \"os_info\": \"$os_info\",
    \"disk_space_available\": \"$disk_space\",
    \"memory_usage\": \"$memory_info\",
    \"docker_version\": \"$docker_version\",
    \"docker_images_count\": $docker_images
  },
  \"diagnostic_info\": {
    \"failure_details\": \"$FAILURE_DETAILS\",
    \"retry_count\": $RETRY_COUNT,
    \"network_interface\": \"$NETWORK_INTERFACE\",
    \"peak_memory_mb\": $PEAK_MEMORY_USAGE,
    \"peak_cpu_percent\": $PEAK_CPU_USAGE
  },
  \"remediation\": {
    \"category\": \"$FAILURE_CATEGORY_ENHANCED\",
    \"suggestions\": \"$REMEDIATION_SUGGESTIONS\",
    \"next_steps\": [
      \"Review the complete build logs for specific error messages\",
      \"Check if similar issues exist in project repository\",
      \"Try reproducing the issue locally for debugging\",
      \"Consider opening an issue with full diagnostic information\",
      \"Analyze the comprehensive error context provided in this report\"
    ]
  },
  \"troubleshooting_commands\": [
    \"df -h              # Check disk space\",
    \"free -h            # Check memory usage\",
    \"docker ps          # Check running containers\",
    \"docker images      # Check available images\",
    \"ps aux             # Check running processes\",
    \"journalctl -f      # Monitor system logs\",
    \"dmesg              # Check kernel messages\",
    \"netstat -i         # Check network interface statistics\",
    \"ulimit -a          # Check resource limits\"
  ]
}"
}

# Collect comprehensive error context
collect_error_context() {
    local failure_stage="$1"
    local failure_reason="$2"
    local error_code="$3"
    local arch="$4"
    local dist="$5"

    local timestamp=$(date -Iseconds)

    # Collect rich environmental information
    ERROR_CONTEXT="{
  \"failure_timestamp\": \"$timestamp\",
  \"build_environment\": {
    \"working_directory\": \"$(pwd)\",
    \"user\": \"$(whoami 2>/dev/null || echo 'unknown')\",
    \"home_directory\": \"$HOME\",
    \"shell\": \"$SHELL\",
    \"path\": \"$PATH\",
    \"timezone\": \"$(timedatectl show --property=Timezone --value 2>/dev/null || echo 'unknown')\",
    \"locale\": \"$(locale 2>/dev/null | grep LC_CTYPE | cut -d= -f2 || echo 'unknown')\"
  },
  \"system_load\": {
    \"load_1min\": \"$(cat /proc/loadavg | awk '{print $1}' 2>/dev/null || echo '0')\",
    \"load_5min\": \"$(cat /proc/loadavg | awk '{print $2}' 2>/dev/null || echo '0')\",
    \"load_15min\": \"$(cat /proc/loadavg | awk '{print $3}' 2>/dev/null || echo '0')\",
    \"running_processes\": \"$(cat /proc/loadavg | awk '{print $4}' 2>/dev/null || echo '0')\"
  },
  \"resource_limits\": {
    \"max_open_files\": \"$(ulimit -n 2>/dev/null || echo 'unknown')\",
    \"max_user_processes\": \"$(ulimit -u 2>/dev/null || echo 'unknown')\",
    \"max_memory\": \"$(ulimit -v 2>/dev/null || echo 'unknown')\",
    \"stack_size\": \"$(ulimit -s 2>/dev/null || echo 'unknown')\"
  },
  \"process_info\": {
    \"build_pid\": \"$$\",
    \"parent_pid\": \"$(ps -o ppid= -p $$ 2>/dev/null | awk '{print $1}' || echo 'unknown')\",
    \"process_tree\": \"$(pstree -p $$ 2>/dev/null || echo 'unknown')\",
    \"environment_size\": \"$(env 2>/dev/null | wc -l || echo '0')\"
  }
}"

    # Collect API response codes and network details
    API_RESPONSE_CODES="{
  \"github_api_status\": \"$(curl -s -o /dev/null -w '%{http_code}' https://api.github.com/rate_limit 2>/dev/null || echo 'failed')\",
  \"github_rate_limit\": \"$(curl -s https://api.github.com/rate_limit 2>/dev/null | jq -r '.rate.remaining // 'unknown'' 2>/dev/null || echo 'unknown')\",
  \"github_rate_limit_reset\": \"$(curl -s https://api.github.com/rate_limit 2>/dev/null | jq -r '.rate.reset // 'unknown'' 2>/dev/null || echo 'unknown')\",
  \"dns_resolution\": \"$(nslookup github.com 2>/dev/null | grep -c 'Address:' || echo '0')\",
  \"connectivity_tests\": {
    \"github\": \"$(timeout 5 ping -c 1 github.com >/dev/null 2>&1 && echo 'success' || echo 'failed')\",
    \"google_dns\": \"$(timeout 5 ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo 'success' || echo 'failed')\",
    \"internet\": \"$(timeout 5 ping -c 1 1.1.1.1 >/dev/null 2>&1 && echo 'success' || echo 'failed')\"
  }
}"

    # Collect system snapshot at failure time
    SYSTEM_SNAPSHOT="{
  \"memory\": {
    \"total_mb\": \"$(free -m | awk '/^Mem:/{print $2}' 2>/dev/null || echo '0')\",
    \"used_mb\": \"$(free -m | awk '/^Mem:/{print $3}' 2>/dev/null || echo '0')\",
    \"free_mb\": \"$(free -m | awk '/^Mem:/{print $4}' 2>/dev/null || echo '0')\",
    \"available_mb\": \"$(free -m | awk '/^Mem:/{print $7}' 2>/dev/null || echo '0')\",
    \"swap_total_mb\": \"$(free -m | awk '/^Swap:/{print $2}' 2>/dev/null || echo '0')\",
    \"swap_used_mb\": \"$(free -m | awk '/^Swap:/{print $3}' 2>/dev/null || echo '0')\"
  },
  \"disk\": {
    \"filesystem\": \"$(df -h . 2>/dev/null | tail -1 | awk '{print $1}' || echo 'unknown')\",
    \"total_gb\": \"$(df -BG . 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo '0')\",
    \"used_gb\": \"$(df -BG . 2>/dev/null | tail -1 | awk '{print $3}' | sed 's/G//' || echo '0')\",
    \"available_gb\": \"$(df -BG . 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo '0')\",
    \"usage_percent\": \"$(df -h . 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo '0')\",
    \"inode_usage\": \"$(df -i . 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo '0')\"
  },
  \"cpu\": {
    \"model\": \"$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo 'unknown')\",
    \"cores\": \"$(nproc 2>/dev/null || echo '0')\",
    \"threads\": \"$(grep -c processor /proc/cpuinfo 2>/dev/null || echo '0')\",
    \"frequency_mhz\": \"$(grep 'cpu MHz' /proc/cpuinfo 2>/dev/null | head -1 | awk '{print $4}' || echo '0')\",
    \"cache_info\": \"$(grep 'cache size' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo 'unknown')\"
  },
  \"processes\": {
    \"total\": \"$(ps aux 2>/dev/null | wc -l || echo '0')\",
    \"running\": \"$(ps aux 2>/dev/null | awk '$8 ~ /^R/ {print}' | wc -l || echo '0')\",
    \"sleeping\": \"$(ps aux 2>/dev/null | awk '$8 ~ /^S/ {print}' | wc -l || echo '0')\",
    \"zombie\": \"$(ps aux 2>/dev/null | awk '$8 ~ /^Z/ {print}' | wc -l || echo '0')\",
    \"top_memory\": \"$(ps aux --sort=-%mem 2>/dev/null | head -5 | awk '{print $11, $4}' || echo 'unknown')\",
    \"top_cpu\": \"$(ps aux --sort=-%cpu 2>/dev/null | head -5 | awk '{print $11, $3}' || echo 'unknown')\"
  }
}"

    # Collect network conditions
    NETWORK_CONDITIONS="{
  \"interface\": \"$NETWORK_INTERFACE\",
  \"interface_status\": \"$(ip link show $NETWORK_INTERFACE 2>/dev/null | grep -o 'state [A-Z]*' | cut -d' ' -f2 || echo 'unknown')\",
  \"ip_addresses\": {
    \"ipv4\": \"$(ip addr show $NETWORK_INTERFACE 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1 || echo 'none')\",
    \"ipv6\": \"$(ip addr show $NETWORK_INTERFACE 2>/dev/null | grep 'inet6 ' | awk '{print $2}' | head -1 || echo 'none')\"
  },
  \"network_stats\": {
    \"rx_bytes\": \"$(cat /proc/net/dev 2>/dev/null | grep $NETWORK_INTERFACE | awk '{print $2}' || echo '0')\",
    \"tx_bytes\": \"$(cat /proc/net/dev 2>/dev/null | grep $NETWORK_INTERFACE | awk '{print $10}' || echo '0')\",
    \"rx_packets\": \"$(cat /proc/net/dev 2>/dev/null | grep $NETWORK_INTERFACE | awk '{print $3}' || echo '0')\",
    \"tx_packets\": \"$(cat /proc/net/dev 2>/dev/null | grep $NETWORK_INTERFACE | awk '{print $11}' || echo '0')\",
    \"rx_errors\": \"$(cat /proc/net/dev 2>/dev/null | grep $NETWORK_INTERFACE | awk '{print $4}' || echo '0')\",
    \"tx_errors\": \"$(cat /proc/net/dev 2>/dev/null | grep $NETWORK_INTERFACE | awk '{print $12}' || echo '0')\"
  },
  \"dns_servers\": \"$(cat /etc/resolv.conf 2>/dev/null | grep nameserver | awk '{print $2}' | tr '\n' ' ' || echo 'unknown')\",
  \"routing\": {
    \"default_gateway\": \"$(ip route | grep default | awk '{print $3}' | head -1 || echo 'none')\",
    \"gateway_interface\": \"$(ip route | grep default | awk '{print $5}' | head -1 || echo 'none')\"
  }
}"

    # Collect build environment details
    ENVIRONMENT_DETAILS="{
  \"build_context\": {
    \"stage\": \"$failure_stage\",
    \"architecture\": \"$arch\",
    \"distribution\": \"$dist\",
    \"package_name\": \"${PACKAGE_NAME:-unknown}\",
    \"version\": \"${VERSION:-unknown}\",
    \"build_version\": \"${BUILD_VERSION:-unknown}\",
    \"github_repo\": \"${GITHUB_REPO:-unknown}\"
  },
  \"container_info\": {
    \"in_container\": \"$(grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null && echo 'true' || echo 'false')\",
    \"container_id\": \"$(cat /proc/self/cgroup 2>/dev/null | grep 'docker' | tail -1 | cut -d/ -f3 | head -c 12 || echo 'none')\",
    \"mount_info\": \"$(mount | grep -E '(docker|overlayfs|aufs)' | wc -l 2>/dev/null || echo '0')\"
  },
  \"security_context\": {
    \"selinux_status\": \"$(getenforce 2>/dev/null || echo 'disabled')\",
    \"apparmor_status\": \"$(aa-status 2>/dev/null | grep -c profiles || echo '0')\",
    \"capabilities\": \"$(capsh --print 2>/dev/null | grep -c 'bounding=' || echo 'unknown')\"
  },
  \"temp_directories\": {
    \"/tmp_space_mb\": \"$(df -m /tmp 2>/dev/null | tail -1 | awk '{print $4}' || echo '0')\",
    \"/tmp_files\": \"$(find /tmp -maxdepth 1 -type f 2>/dev/null | wc -l || echo '0')\",
    \"temp_dir_usage\": \"$(du -sm /tmp 2>/dev/null | awk '{print $1}' || echo '0')\"
  }
}"

    # Collect diagnostic data
    collect_diagnostic_data "$failure_stage" "$failure_reason"
}

# Collect diagnostic data automatically
collect_diagnostic_data() {
    local failure_stage="$1"
    local failure_reason="$2"

    DIAGNOSTIC_DATA="{
  \"recent_logs\": {
    \"system_messages\": \"$(journalctl --since '10 minutes ago' --priority=0..3 --no-pager -n 20 2>/dev/null | tail -10 | sed 's/"/\\"/g' | tr '\n' ';' || echo 'unavailable')\",
    \"docker_logs\": \"$(journalctl -u docker --since '10 minutes ago' --no-pager -n 10 2>/dev/null | tail -5 | sed 's/"/\\"/g' | tr '\n' ';' || echo 'unavailable')\",
    \"kernel_messages\": \"$(dmesg | tail -20 2>/dev/null | sed 's/"/\\"/g' | tr '\n' ';' || echo 'unavailable')\"
  },
  \"file_system\": {
    \"disk_errors\": \"$(dmesg | grep -i 'error\|fail' | grep -i 'disk\|fs\|ext' | tail -5 2>/dev/null | sed 's/"/\\"/g' | tr '\n' ';' || echo 'none')\",
    \"corrupted_files\": \"$(find . -name '*.deb' -size 0 2>/dev/null | head -5 | tr '\n' ';' || echo 'none')\",
    \"permission_issues\": \"$(find . -name '*.log' -perm 000 2>/dev/null | head -5 | tr '\n' ';' || echo 'none')\"
  },
  \"network_diagnostics\": {
    \"dns_resolution_time\": \"$(dig github.com +time=5 +tries=1 2>/dev/null | grep 'Query time' | awk '{print $4}' || echo 'failed')\",
    \"connection_latency_ms\": \"$(ping -c 1 github.com 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}' || echo 'failed')\",
    \"traceroute_hops\": \"$(traceroute -m 5 github.com 2>/dev/null | wc -l || echo '0')\",
    \"port_connectivity\": \"$(timeout 3 bash -c 'echo >/dev/tcp/github.com/443' 2>/dev/null && echo 'success' || echo 'failed')\"
  },
  \"build_artifacts\": {
    \"partial_packages\": \"$(find . -name '*.deb' -size +0c 2>/dev/null | wc -l || echo '0')\",
    \"empty_packages\": \"$(find . -name '*.deb' -size 0 2>/dev/null | wc -l || echo '0')\",
    \"corrupted_packages\": \"$(find . -name '*.deb' -exec file {} \; 2>/dev/null | grep -v 'Debian' | wc -l || echo '0')\",
    \"log_files\": \"$(find . -name '*.log' -size +0c 2>/dev/null | wc -l || echo '0')\"
  },
  \"performance_indicators\": {
    \"io_wait\": \"$(iostat -x 1 1 2>/dev/null | grep -E '(Device|$NETWORK_INTERFACE)' | tail -1 | awk '{print $10}' || echo '0')\",
    \"context_switches\": \"$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $12}' || echo '0')\",
    \"swap_activity\": \"$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $7}' || echo '0')\",
    \"interrupts_per_sec\": \"$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $11}' || echo '0')\"
  }
}"
}

# Initialize build state tracking
initialize_build_state() {
    local architectures="$1"
    local distributions="$2"

    if [ "$TELEMETRY_ENABLED" != "true" ]; then
        return 0
    fi

    local timestamp=$(date -Iseconds)
    local build_id="${PACKAGE_NAME}-${VERSION}-${BUILD_VERSION}-$(date +%s)"

    # Create initial state structure
    local initial_state="{
  \"build_id\": \"$build_id\",
  \"timestamp\": \"$timestamp\",
  \"package_name\": \"${PACKAGE_NAME:-unknown}\",
  \"version\": \"${VERSION:-unknown}\",
  \"build_version\": \"${BUILD_VERSION:-unknown}\",
  \"github_repo\": \"${GITHUB_REPO:-unknown}\",
  \"architectures\": [$(echo "$architectures" | sed 's/[^ ]\+/"&"/g' | tr ' ' ',' | sed 's/,$//')],
  \"distributions\": [$(echo "$distributions" | sed 's/[^ ]\+/"&"/g' | tr ' ' ',' | sed 's/,$//')],
  \"state\": \"initializing\",
  \"started_at\": \"$timestamp\",
  \"completed_at\": null,
  \"build_progress\": {
    \"total_packages\": 0,
    \"completed_packages\": 0,
    \"failed_packages\": 0,
    \"skipped_packages\": 0,
    \"pending_packages\": 0
  },
  \"architecture_states\": {},
  \"completed_builds\": [],
  \"failed_builds\": [],
  \"skipped_builds\": [],
  \"pending_builds\": [],
  \"build_details\": {}
}"

    # Initialize per-architecture states
    local arch_array=($architectures)
    local dist_array=($distributions)

    for arch in "${arch_array[@]}"; do
        for dist in "${dist_array[@]}"; do
            if is_arch_supported_for_dist "$arch" "$dist"; then
                initial_state=$(echo "$initial_state" | jq --arg arch "$arch" --arg dist "$dist" '
                    .architecture_states[$arch][$dist] = {
                        "state": "pending",
                        "started_at": null,
                        "completed_at": null,
                        "status": "pending",
                        "attempt_count": 0,
                        "last_attempt": null,
                        "output_files": [],
                        "log_file": null,
                        "error_details": null
                    } |
                    .pending_builds += [{"architecture": $arch, "distribution": $dist}]
                ')
            fi
        done
    done

    # Update total packages count
    initial_state=$(echo "$initial_state" | jq '
        .build_progress.total_packages = (.pending_builds | length)
    ')

    # Save initial state
    echo "$initial_state" > "$BUILD_STATE_FILE"
    info "Build state initialized with $(echo "$initial_state" | jq '.build_progress.total_packages') packages to build"

    # Export state variables for easy access
    PENDING_BUILDS=$(echo "$initial_state" | jq -r '.pending_builds | length')
    COMPLETED_BUILDS="0"
    FAILED_BUILDS="0"
    SKIPPED_BUILDS="0"
}

# Update build state for architecture/distribution
update_build_state() {
    local arch="$1"
    local dist="$2"
    local status="$3"  # started, completed, failed, skipped
    local details="$4"  # Optional error details or additional info

    if [ "$TELEMETRY_ENABLED" != "true" ] || [ ! -f "$BUILD_STATE_FILE" ]; then
        return 0
    fi

    local timestamp=$(date -Iseconds)
    local state_update=""

    case "$status" in
        "started")
            state_update=$(jq --arg arch "$arch" --arg dist "$dist" --arg timestamp "$timestamp" '
                .architecture_states[$arch][$dist].state = "building" |
                .architecture_states[$arch][$dist].started_at = $timestamp |
                .architecture_states[$arch][$dist].status = "building" |
                .architecture_states[$arch][$dist].attempt_count += 1 |
                .architecture_states[$arch][$dist].last_attempt = $timestamp
            ' "$BUILD_STATE_FILE")
            ;;
        "completed")
            state_update=$(jq --arg arch "$arch" --arg dist "$dist" --arg timestamp "$timestamp" '
                .architecture_states[$arch][$dist].state = "completed" |
                .architecture_states[$arch][$dist].completed_at = $timestamp |
                .architecture_states[$arch][$dist].status = "completed" |
                .completed_builds += [{"architecture": $arch, "distribution": $dist, "completed_at": $timestamp}]
            ' "$BUILD_STATE_FILE")
            ;;
        "failed")
            state_update=$(jq --arg arch "$arch" --arg dist "$dist" --arg timestamp "$timestamp" --arg details "$details" '
                .architecture_states[$arch][$dist].state = "failed" |
                .architecture_states[$arch][$dist].completed_at = $timestamp |
                .architecture_states[$arch][$dist].status = "failed" |
                .architecture_states[$arch][$dist].error_details = $details |
                .failed_builds += [{"architecture": $arch, "distribution": $dist, "failed_at": $timestamp, "error": $details}]
            ' "$BUILD_STATE_FILE")
            ;;
        "skipped")
            state_update=$(jq --arg arch "$arch" --arg dist "$dist" --arg timestamp "$timestamp" --arg details "$details" '
                .architecture_states[$arch][$dist].state = "skipped" |
                .architecture_states[$arch][$dist].completed_at = $timestamp |
                .architecture_states[$arch][$dist].status = "skipped" |
                .architecture_states[$arch][$dist].error_details = $details |
                .skipped_builds += [{"architecture": $arch, "distribution": $dist, "skipped_at": $timestamp, "reason": $details}]
            ' "$BUILD_STATE_FILE")
            ;;
    esac

    # Remove from pending builds and update counts
    state_update=$(echo "$state_update" | jq --arg arch "$arch" --arg dist "$dist" '
        .pending_builds = [.pending_builds[] | select(.architecture != $arch or .distribution != $dist)] |
        .build_progress.completed_packages = (.completed_builds | length) |
        .build_progress.failed_packages = (.failed_builds | length) |
        .build_progress.skipped_packages = (.skipped_builds | length) |
        .build_progress.pending_packages = (.pending_builds | length)
    ')

    # Update overall state if all builds are done
    local total_done=$(echo "$state_update" | jq '(.completed_builds | length) + (.failed_builds | length) + (.skipped_builds | length)')
    local total_packages=$(echo "$state_update" | jq '.build_progress.total_packages')

    if [ "$total_done" -eq "$total_packages" ]; then
        local final_state="completed"
        if [ "$(echo "$state_update" | jq '.failed_builds | length')" -gt 0 ]; then
            final_state="completed_with_failures"
        fi
        state_update=$(echo "$state_update" | jq --arg final_state "$final_state" --arg timestamp "$timestamp" '
            .state = $final_state |
            .completed_at = $timestamp
        ')
    fi

    echo "$state_update" > "$BUILD_STATE_FILE"

    # Update exported variables
    PENDING_BUILDS=$(echo "$state_update" | jq -r '.build_progress.pending_packages')
    COMPLETED_BUILDS=$(echo "$state_update" | jq -r '.build_progress.completed_packages')
    FAILED_BUILDS=$(echo "$state_update" | jq -r '.build_progress.failed_packages')
    SKIPPED_BUILDS=$(echo "$state_update" | jq -r '.build_progress.skipped_packages')
}

# Get current build state summary
get_build_state_summary() {
    if [ "$TELEMETRY_ENABLED" != "true" ] || [ ! -f "$BUILD_STATE_FILE" ]; then
        echo "{}"
        return 0
    fi

    jq '{
        build_id: .build_id,
        package_name: .package_name,
        version: .version,
        state: .state,
        progress: .build_progress,
        architecture_count: (.architectures | length),
        distribution_count: (.distributions | length),
        started_at: .started_at,
        completed_at: .completed_at,
        recent_activity: (.completed_builds[-3:] + .failed_builds[-3:] + .skipped_builds[-3:]),
        pending_count: (.pending_builds | length),
        architecture_states: .architecture_states
    }' "$BUILD_STATE_FILE"
}

# Display build state summary
display_build_state_summary() {
    if [ "$TELEMETRY_ENABLED" != "true" ] || [ ! -f "$BUILD_STATE_FILE" ]; then
        return 0
    fi

    local summary=$(get_build_state_summary)
    local state=$(echo "$summary" | jq -r '.state')
    local total=$(echo "$summary" | jq -r '.progress.total_packages')
    local completed=$(echo "$summary" | jq -r '.progress.completed_packages')
    local failed=$(echo "$summary" | jq -r '.progress.failed_packages')
    local skipped=$(echo "$summary" | jq -r '.progress.skipped_packages')
    local pending=$(echo "$summary" | jq -r '.progress.pending_packages')
    local progress_pct=0

    if [ "$total" -gt 0 ]; then
        progress_pct=$(( (completed + failed + skipped) * 100 / total ))
    fi

    echo ""
    echo "📊 BUILD STATE SUMMARY"
    echo "=========================================="
    echo "🔍 State: $state"
    echo "📦 Total Packages: $total"
    echo "✅ Completed: $completed"
    echo "❌ Failed: $failed"
    echo "⏭️  Skipped: $skipped"
    echo "⏳ Pending: $pending"
    echo "📈 Progress: $progress_pct%"
    echo ""

    if [ "$pending" -gt 0 ]; then
        echo "🔄 PENDING BUILDS:"
        echo "$summary" | jq -r '.pending_builds[] | "   • \(.architecture)/\(.distribution)"' | head -10
        if [ "$pending" -gt 10 ]; then
            echo "   ... and $((pending - 10)) more"
        fi
        echo ""
    fi

    if [ "$failed" -gt 0 ]; then
        echo "❌ FAILED BUILDS:"
        echo "$summary" | jq -r '.failed_builds[-5:][] | "   • \(.architecture)/\(.distribution): \(.error // "unknown error")"' | head -5
        echo ""
    fi

    echo "📄 Detailed state file: $BUILD_STATE_FILE"
    echo "=========================================="
    echo ""
}

# Export state tracking functions
export -f initialize_build_state
export -f update_build_state
export -f get_build_state_summary
export -f display_build_state_summary

# Enhanced record failure with retry logic
record_build_failure_with_retry() {
    local failure_stage="$1"
    local failure_reason="$2"
    local error_code="$3"
    local max_retries="${4:-3}"

    # Classify the failure first
    classify_failure_type "$failure_stage" "$failure_reason" "$error_code"

    if [ "$FAILURE_TYPE" = "transient" ] && [ "$RETRY_COUNT" -lt "$max_retries" ]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        info "Transient failure detected (attempt $RETRY_COUNT/$max_retries): $FAILURE_DETAILS"
        info "Retrying $failure_stage..."

        # Update telemetry with retry attempt
        update_telemetry_field "build_metrics.retry_count" "$RETRY_COUNT"
        update_telemetry_field "build_metrics.last_retry_attempt" "$(date -Iseconds)"

        return 2  # Signal that retry should be attempted
    else
        # Record the permanent failure or max retries reached
        record_build_failure "$failure_stage" "$failure_reason" "$error_code"

        if [ "$FAILURE_TYPE" = "transient" ]; then
            warning "Maximum retries ($max_retries) exceeded for transient failure"
        else
            error "Permanent failure detected: $FAILURE_DETAILS"
        fi

        return 1  # Signal failure
    fi
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
    if [ -f "$TELEMETRY_DIR/resource-monitor.pid" ]; then
        kill $(cat "$TELEMETRY_DIR/resource-monitor.pid") 2>/dev/null || true
        rm -f "$TELEMETRY_DIR/resource-monitor.pid"
    fi

    if [ -f "$TELEMETRY_DIR/memory-monitor.pid" ]; then
        kill $(cat "$TELEMETRY_DIR/memory-monitor.pid") 2>/dev/null || true
        rm -f "$TELEMETRY_DIR/memory-monitor.pid"
    fi

    if [ -f "$TELEMETRY_DIR/network-monitor.pid" ]; then
        kill $(cat "$TELEMETRY_DIR/network-monitor.pid") 2>/dev/null || true
        rm -f "$TELEMETRY_DIR/network-monitor.pid"
    fi

    # Collect final resource peak values
    if [ -f "$TELEMETRY_DIR/current-peak-memory.txt" ]; then
        PEAK_MEMORY_USAGE=$(cat "$TELEMETRY_DIR/current-peak-memory.txt")
        echo "Final peak memory usage: ${PEAK_MEMORY_USAGE}MB"
    else
        PEAK_MEMORY_USAGE=0
    fi

    if [ -f "$TELEMETRY_DIR/current-peak-cpu.txt" ]; then
        PEAK_CPU_USAGE=$(cat "$TELEMETRY_DIR/current-peak-cpu.txt")
        echo "Final peak CPU usage: ${PEAK_CPU_USAGE}%"
    else
        PEAK_CPU_USAGE=0
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

        # Check if telemetry file exists
        if [ ! -f "$TELEMETRY_DATA_FILE" ]; then
            echo "🔍 TELEMETRY ERROR: Telemetry file not found: $TELEMETRY_DATA_FILE"
            return 1
        fi

        # Use proper quoting for date values to avoid yq parsing issues
        local start_time_iso=$(date -d "@$BUILD_START_TIME" -Iseconds)
        local end_time_iso=$(date -d "@$BUILD_END_TIME" -Iseconds)

        echo "🔍 TELEMETRY: Updating telemetry file: $TELEMETRY_DATA_FILE"

        # Update all fields in single command to avoid file locking issues
        if yq eval "
            .build_session.start_time = \"$start_time_iso\" |
            .build_session.end_time = \"$end_time_iso\" |
            .build_session.duration_seconds = $build_duration |
            .memory_metrics.peak_usage_mb = $PEAK_MEMORY_USAGE |
            .cpu_metrics.peak_usage_percent = $PEAK_CPU_USAGE |
            .network_metrics.bytes_downloaded = $NETWORK_BYTES_DOWNLOADED |
            .network_metrics.bytes_uploaded = $NETWORK_BYTES_UPLOADED
        " -i "$TELEMETRY_DATA_FILE"; then
            echo "🔍 TELEMETRY: Successfully updated all telemetry fields"
            echo "🔍 TELEMETRY: Duration=${build_duration}s, Memory=${PEAK_MEMORY_USAGE}MB, CPU=${PEAK_CPU_USAGE}%, Down=${NETWORK_BYTES_DOWNLOADED}, Up=${NETWORK_BYTES_UPLOADED}"
        else
            echo "🔍 TELEMETRY ERROR: Failed to update telemetry file"
            # Fall back to manual updates
            echo "🔍 TELEMETRY: Trying individual field updates..."

            yq eval ".build_session.duration_seconds = $build_duration" -i "$TELEMETRY_DATA_FILE" || echo "ERROR: Failed to update duration"
            yq eval ".memory_metrics.peak_usage_mb = $PEAK_MEMORY_USAGE" -i "$TELEMETRY_DATA_FILE" || echo "ERROR: Failed to update memory"
            yq eval ".cpu_metrics.peak_usage_percent = $PEAK_CPU_USAGE" -i "$TELEMETRY_DATA_FILE" || echo "ERROR: Failed to update CPU"
            yq eval ".network_metrics.bytes_downloaded = $NETWORK_BYTES_DOWNLOADED" -i "$TELEMETRY_DATA_FILE" || echo "ERROR: Failed to update download"
            yq eval ".network_metrics.bytes_uploaded = $NETWORK_BYTES_UPLOADED" -i "$TELEMETRY_DATA_FILE" || echo "ERROR: Failed to update upload"
        fi
    else
        echo "🔍 TELEMETRY ERROR: yq command not found"
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
            peak_cpu_percent: .cpu_metrics.peak_usage_percent,
            network_downloaded_bytes: .network_metrics.bytes_downloaded,
            network_uploaded_bytes: .network_metrics.bytes_uploaded,
            failure_category: .build_metrics.failure_category,
            failure_stage: .build_metrics.failure_stage,
            failure_reason: .build_metrics.failure_reason,
            failure_details: .build_metrics.failure_details,
            failure_code: .build_metrics.failure_code,
            failure_type: .build_metrics.failure_type,
            failure_details_summary: .build_metrics.failure_details_summary,
            failure_category_enhanced: .build_metrics.failure_category_enhanced,
            remediation_suggestions: .build_metrics.remediation_suggestions,
            retry_count: .build_metrics.retry_count,
            last_retry_attempt: .build_metrics.last_retry_attempt,
            error_context: .build_metrics.error_context,
            api_response_codes: .build_metrics.api_response_codes,
            system_snapshot: .build_metrics.system_snapshot,
            network_conditions: .build_metrics.network_conditions,
            environment_details: .build_metrics.environment_details,
            diagnostic_data: .build_metrics.diagnostic_data,
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
export -f record_build_failure_with_retry
export -f classify_failure_type
export -f categorize_failure_enhanced
export -f generate_detailed_failure_report
export -f collect_error_context
export -f collect_diagnostic_data
export -f finalize_telemetry
export -f get_telemetry_summary
export -f save_as_baseline
export -f add_failure_detail
export -f collect_docker_info
export -f collect_system_resources
export -f update_final_system_resources