#!/bin/bash

# Success/failure reporting and resource usage utilities

# Common success/failure summary utilities
show_build_summary() {
    local total_packages="$1"
    local attempted_packages="$2"
    local success_rate="$3"

    if [ "$total_packages" -eq "$attempted_packages" ]; then
        success "All attempted architectures built successfully!"
    elif [ "$total_packages" -gt 0 ]; then
        success "Build completed with partial success (${success_rate}% success rate)"
    else
        warning "Build completed but no packages were generated!"
    fi
}

calculate_success_rate() {
    local built="$1"
    local attempted="$2"

    if [ "$attempted" -gt 0 ]; then
        echo $(( (built * 100) / attempted ))
    else
        echo "0"
    fi
}

# Resource reporting utilities
report_resource_usage() {
    if [ "$TELEMETRY_ENABLED" = "true" ]; then
        local peak_mem=$(cat ".telemetry/current-peak-memory.txt" 2>/dev/null || echo "0")
        local peak_cpu=$(cat ".telemetry/current-peak-cpu.txt" 2>/dev/null || echo "0")

        if [ "$peak_mem" -gt 0 ] || [ "$peak_cpu" -gt 0 ]; then
            echo "  📊 Resource Usage: Peak ${peak_mem}MB memory, Peak ${peak_cpu}% CPU"
        fi
    fi
}