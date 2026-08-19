#!/bin/bash

# Utility functions for loading YAML configuration files

# Load CI environment specifications
load_ci_environment_specs() {
    local data_file="$SCRIPT_DIR/data/ci-environments.yaml"

    if [ ! -f "$data_file" ]; then
        echo "ERROR: CI environment specifications file not found: $data_file" >&2
        return 1
    fi

    # Set the CI specs file location for later use
    export CI_ENV_SPECS_DATA="$data_file"
}

# Get auto-discovery preferences
get_auto_discovery_preferences() {
    local data_file="$SCRIPT_DIR/data/architecture-patterns.yaml"

    if [ ! -f "$data_file" ]; then
        return 1
    fi

    yq eval ".auto_discovery_preferences[]" "$data_file" 2>/dev/null
}

# Get resource-based parallel limits
get_resource_parallel_limit() {
    local cores=$1
    local memory_gb=$2
    local data_file="$SCRIPT_DIR/data/ci-environments.yaml"

    if [ ! -f "$data_file" ]; then
        echo "2"  # Default fallback
        return 0
    fi

    # Look up the limit for the specific cores:memory combination
    local limit=$(yq eval ".resource_parallel_limits.\"${cores}:${memory_gb}\"" "$data_file" 2>/dev/null)

    if [ -z "$limit" ] || [ "$limit" = "null" ]; then
        # Find closest matching resource limit if exact match not found
        local closest_limit="2"

        # Use more sophisticated resource matching logic if needed
        if [ "$cores" -ge 8 ] && [ "$memory_gb" -ge 32 ]; then
            closest_limit="6"
        elif [ "$cores" -ge 4 ] && [ "$memory_gb" -ge 16 ]; then
            closest_limit="4"
        elif [ "$cores" -ge 2 ] && [ "$memory_gb" -ge 7 ]; then
            closest_limit="2"
        else
            closest_limit="1"
        fi

        echo "$closest_limit"
    else
        echo "$limit"
    fi
}
