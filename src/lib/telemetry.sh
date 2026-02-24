#!/bin/bash

# Minimal Telemetry System - Restores functionality after modularization
# This provides the essential telemetry functions that the build system expects

# Global telemetry configuration
TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-false}"
TELEMETRY_DIR=".telemetry"

# Initialize telemetry system
init_telemetry() {
    if [ "$TELEMETRY_ENABLED" = "false" ]; then
        return 0
    fi
    
    mkdir -p "$TELEMETRY_DIR"
    
    # Initialize basic metrics
    export BUILD_START_TIME=$(date +%s)
    export PEAK_MEMORY_USAGE=0
    export NETWORK_BYTES_DOWNLOADED=0
    
    # Create basic metrics file
    cat > "$TELEMETRY_DIR/metrics.json" << EOF
{
  "build_start_time": $BUILD_START_TIME,
  "telemetry_enabled": true
}
EOF
}

# Record build failure
record_build_failure() {
    local category="$1"
    local details="$2"
    local exit_code="${3:-1}"
    
    if [ "$TELEMETRY_ENABLED" = "false" ]; then
        return 0
    fi
    
    # Basic failure logging
    echo "Build failure recorded: $category - $details (exit code: $exit_code)" >> "$TELEMETRY_DIR/failures.log"
}

# Record build stage
record_build_stage() {
    local stage="$1"
    
    if [ "$TELEMETRY_ENABLED" = "false" ]; then
        return 0
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Stage: $stage" >> "$TELEMETRY_DIR/stages.log"
}

# Record build stage completion
record_build_stage_complete() {
    local stage="$1"
    local status="${2:-success}"
    
    if [ "$TELEMETRY_ENABLED" = "false" ]; then
        return 0
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Stage complete: $stage ($status)" >> "$TELEMETRY_DIR/stages.log"
}

# Finalize telemetry
finalize_telemetry() {
    if [ "$TELEMETRY_ENABLED" = "false" ]; then
        return 0
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - BUILD_START_TIME))
    
    # Update metrics with completion data
    cat >> "$TELEMETRY_DIR/metrics.json" << EOF
,
  "build_end_time": $end_time,
  "build_duration": $duration,
  "build_completed": true
}
EOF
}

# Add failure detail (for compatibility)
add_failure_detail() {
    local key="$1"
    local value="$2"
    
    if [ "$TELEMETRY_ENABLED" = "false" ]; then
        return 0
    fi
    
    echo "Failure detail: $key = $value" >> "$TELEMETRY_DIR/failure_details.log"
}

# Cleanup telemetry files
cleanup_telemetry() {
    if [ "$TELEMETRY_ENABLED" = "false" ]; then
        return 0
    fi
    
    # Remove temporary telemetry files
    rm -f "$TELEMETRY_DIR"/{*.log,*.tmp}
}

# Resource monitoring (minimal implementation)
start_resource_monitoring() {
    if [ "$TELEMETRY_ENABLED" = "false" ]; then
        return 0
    fi
    
    # No-op for minimal implementation
    return 0
}

stop_resource_monitoring() {
    if [ "$TELEMETRY_ENABLED" = "false" ]; then
        return 0
    fi
    
    # No-op for minimal implementation  
    return 0
}