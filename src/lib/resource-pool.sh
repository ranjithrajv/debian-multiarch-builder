#!/bin/bash

# Enhanced resource pooling and management functions

# Resource pool configuration
RESOURCE_POOL_STATE_DIR="/tmp/resource_pool"
mkdir -p "$RESOURCE_POOL_STATE_DIR"

# Resource tracking variables
declare -A RESOURCE_ALLOCATIONS
declare -A RESOURCE_LIMITS
declare -A RESOURCE_USAGE

# Initialize resource pool
init_resource_pool() {
    local max_parallel="${1:-4}"
    local available_memory_mb="${2:-$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo "2048")}"
    local available_cores="${3:-$(nproc 2>/dev/null || echo "2")}"
    
    # Set resource limits
    RESOURCE_LIMITS[memory]=$available_memory_mb
    RESOURCE_LIMITS[cores]=$available_cores
    RESOURCE_LIMITS[max_jobs]=$max_parallel
    
    # Resource requirements per job
    local min_memory_per_job=1024  # 1GB minimum
    local min_cores_per_job=1      # 1 core minimum
    
    # Calculate sustainable job count
    local memory_limit=$((available_memory_mb / min_memory_per_job))
    local core_limit=$((available_cores / min_cores_per_job))
    local sustainable_jobs=$((memory_limit < core_limit ? memory_limit : core_limit))
    
    # Apply the more restrictive limit
    if [ $sustainable_jobs -lt $max_parallel ]; then
        RESOURCE_LIMITS[max_jobs]=$sustainable_jobs
        warning "Resource-aware adjustment: Using $sustainable_jobs parallel jobs (was $max_parallel)"
    fi
    
    # Initialize usage tracking
    RESOURCE_USAGE[memory]=0
    RESOURCE_USAGE[cores]=0
    RESOURCE_USAGE[jobs]=0
    
    # Create allocation tracking file
    echo "$(date +%s)" > "${RESOURCE_POOL_STATE_DIR}/pool_init_time"
    
    export RESOURCE_LIMITS RESOURCE_USAGE RESOURCE_ALLOCATIONS
}

# Acquire resources for a job
acquire_resources() {
    local job_id="$1"
    local memory_mb="${2:-1024}"
    local cores="${3:-1}"
    
    local state_file="${RESOURCE_POOL_STATE_DIR}/job_${job_id}"
    
    # Use file locking for thread-safe resource acquisition
    (
        flock -x 200
        
        # Read current state
        load_resource_state
        
        # Check if resources are available
        local available_memory=$((RESOURCE_LIMITS[memory] - RESOURCE_USAGE[memory]))
        local available_cores=$((RESOURCE_LIMITS[cores] - RESOURCE_USAGE[cores]))
        local available_jobs=$((RESOURCE_LIMITS[max_jobs] - RESOURCE_USAGE[jobs]))
        
        if [ $available_memory -lt $memory_mb ] || [ $available_cores -lt $cores ] || [ $available_jobs -lt 1 ]; then
            echo "INSUFFICIENT_RESOURCES:$available_memory:$available_cores:$available_jobs"
            exit 1
        fi
        
        # Allocate resources
        RESOURCE_ALLOCATIONS[${job_id}_memory]=$memory_mb
        RESOURCE_ALLOCATIONS[${job_id}_cores]=$cores
        RESOURCE_USAGE[memory]=$((${RESOURCE_USAGE[memory]} + memory_mb))
        RESOURCE_USAGE[cores]=$((${RESOURCE_USAGE[cores]} + cores))
        RESOURCE_USAGE[jobs]=$((${RESOURCE_USAGE[jobs]} + 1))
        
        # Save state
        save_resource_state
        echo "ALLOCATED:$memory_mb:$cores"
        
    ) 200>"${RESOURCE_POOL_STATE_DIR}.lock"
    
    local result=$?
    if [ $result -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Release resources from a job
release_resources() {
    local job_id="$1"
    
    (
        flock -x 200
        
        # Read current state
        load_resource_state
        
        # Check if job has allocations
        local allocated_memory=${RESOURCE_ALLOCATIONS[${job_id}_memory]:-0}
        local allocated_cores=${RESOURCE_ALLOCATIONS[${job_id}_cores]:-0}
        
        # Release resources
        if [ $allocated_memory -gt 0 ] || [ $allocated_cores -gt 0 ]; then
            RESOURCE_USAGE[memory]=$((${RESOURCE_USAGE[memory]} - allocated_memory))
            RESOURCE_USAGE[cores]=$((${RESOURCE_USAGE[cores]} - allocated_cores))
            RESOURCE_USAGE[jobs]=$((${RESOURCE_USAGE[jobs]} - 1))
            
            # Clear allocation records
            unset RESOURCE_ALLOCATIONS[${job_id}_memory]
            unset RESOURCE_ALLOCATIONS[${job_id}_cores]
            
            # Remove job state file
            rm -f "${RESOURCE_POOL_STATE_DIR}/job_${job_id}"
            
            # Save state
            save_resource_state
        fi
        
    ) 200>"${RESOURCE_POOL_STATE_DIR}.lock"
}

# Load resource state from files
load_resource_state() {
    local usage_file="${RESOURCE_POOL_STATE_DIR}/usage"
    local alloc_file="${RESOURCE_POOL_STATE_DIR}/allocations"
    
    if [ -f "$usage_file" ]; then
        source "$usage_file"
    fi
    
    if [ -f "$alloc_file" ]; then
        source "$alloc_file"
    fi
}

# Save resource state to files
save_resource_state() {
    local usage_file="${RESOURCE_POOL_STATE_DIR}/usage"
    local alloc_file="${RESOURCE_POOL_STATE_DIR}/allocations"
    
    # Save usage
    cat > "$usage_file" << EOF
RESOURCE_USAGE[memory]=${RESOURCE_USAGE[memory]}
RESOURCE_USAGE[cores]=${RESOURCE_USAGE[cores]}
RESOURCE_USAGE[jobs]=${RESOURCE_USAGE[jobs]}
EOF
    
    # Save allocations
    {
        for key in "${!RESOURCE_ALLOCATIONS[@]}"; do
            echo "RESOURCE_ALLOCATIONS[$key]=${RESOURCE_ALLOCATIONS[$key]}"
        done
    } > "$alloc_file"
}

# Get current resource availability
get_resource_availability() {
    load_resource_state
    
    local available_memory=$((RESOURCE_LIMITS[memory] - RESOURCE_USAGE[memory]))
    local available_cores=$((RESOURCE_LIMITS[cores] - RESOURCE_USAGE[cores]))
    local available_jobs=$((RESOURCE_LIMITS[max_jobs] - RESOURCE_USAGE[jobs]))
    
    echo "$available_memory:$available_cores:$available_jobs"
}

# Monitor resource usage during build
monitor_job_resources() {
    local job_id="$1"
    local pid="$2"
    local monitor_interval="${3:-5}"
    
    # Start monitoring in background
    (
        while kill -0 "$pid" 2>/dev/null; do
            local memory_usage=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print $1}' || echo "0")
            local cpu_usage=$(ps -o %cpu= -p "$pid" 2>/dev/null | awk '{print int($1)}' || echo "0")
            
            if [ -n "$memory_usage" ] && [ "$memory_usage" -gt 0 ]; then
                echo "$(date +%s):${job_id}:memory:$memory_usage" >> "${RESOURCE_POOL_STATE_DIR}/job_monitor.log"
            fi
            
            if [ -n "$cpu_usage" ] && [ "$cpu_usage" -gt 0 ]; then
                echo "$(date +%s):${job_id}:cpu:$cpu_usage" >> "${RESOURCE_POOL_STATE_DIR}/job_monitor.log"
            fi
            
            sleep $monitor_interval
        done
    ) &
    
    echo $!
}

# Cleanup resource pool
cleanup_resource_pool() {
    # Release any remaining allocations
    for job_file in "${RESOURCE_POOL_STATE_DIR}"/job_*; do
        if [ -f "$job_file" ]; then
            local job_id=$(basename "$job_file" | sed 's/job_//')
            release_resources "$job_id"
        fi
    done
    
    # Clean up state files
    rm -rf "$RESOURCE_POOL_STATE_DIR" 2>/dev/null || true
}

# Enhanced graceful degradation using resource pooling
apply_enhanced_degradation() {
    local requested_jobs="$1"
    
    # Initialize resource pool if not already done
    if [ ! -f "${RESOURCE_POOL_STATE_DIR}/pool_init_time" ]; then
        init_resource_pool "$requested_jobs"
    fi
    
    load_resource_state
    
    echo "${RESOURCE_LIMITS[max_jobs]}"
}

# Get resource usage statistics
get_resource_stats() {
    load_resource_state
    
    echo "Resource Pool Statistics:"
    echo "  Memory: ${RESOURCE_USAGE[memory]}MB / ${RESOURCE_LIMITS[memory]}MB used"
    echo "  Cores: ${RESOURCE_USAGE[cores]} / ${RESOURCE_LIMITS[cores]} used"
    echo "  Jobs: ${RESOURCE_USAGE[jobs]} / ${RESOURCE_LIMITS[max_jobs]} running"
    echo "  Available: $(get_resource_availability)"
}

# Export functions for use in other scripts
export -f init_resource_pool
export -f acquire_resources
export -f release_resources
export -f get_resource_availability
export -f monitor_job_resources
export -f cleanup_resource_pool
export -f apply_enhanced_degradation
export -f get_resource_stats