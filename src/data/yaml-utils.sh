#!/bin/bash

# Utility functions for loading YAML configuration files

# Load architecture support data
load_architecture_support() {
    local data_file="$SCRIPT_DIR/data/architecture-support.yaml"
    
    if [ ! -f "$data_file" ]; then
        echo "ERROR: Architecture support data file not found: $data_file" >&2
        return 1
    fi
    
    # Load the restricted architectures data
    export RESTRICTED_ARCHS_DATA="$data_file"
}

# Load architecture patterns data
load_architecture_patterns() {
    local data_file="$SCRIPT_DIR/data/architecture-patterns.yaml"
    
    if [ ! -f "$data_file" ]; then
        echo "ERROR: Architecture patterns data file not found: $data_file" >&2
        return 1
    fi
    
    # Set the patterns file location for later use
    export ARCH_PATTERNS_DATA="$data_file"
}

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

# Get supported distributions for an architecture from YAML data
get_supported_distributions_for_arch() {
    local arch=$1
    local data_file="$SCRIPT_DIR/data/architecture-support.yaml"
    
    if [ ! -f "$data_file" ]; then
        return 1
    fi
    
    # Extract supported distributions for this architecture from YAML
    local supported_dists=$(yq eval ".debian_architecture_support.\"$arch\".supported_distributions[]" "$data_file" 2>/dev/null)
    
    if [ -n "$supported_dists" ] && [ "$supported_dists" != "null" ]; then
        echo "$supported_dists"
        return 0
    else
        # If not found in restricted list, assume supported on all distributions
        yq eval ".distributions.valid[]" "$SCRIPT_DIR/data/distributions.yaml" 2>/dev/null
    fi
}

# Get architecture pattern for auto-discovery
get_architecture_pattern() {
    local arch=$1
    local data_file="$SCRIPT_DIR/data/architecture-patterns.yaml"
    
    if [ ! -f "$data_file" ]; then
        return 1
    fi
    
    yq eval ".architecture_patterns.\"$arch\"" "$data_file" 2>/dev/null
}

# Get auto-discovery preferences
get_auto_discovery_preferences() {
    local data_file="$SCRIPT_DIR/data/architecture-patterns.yaml"
    
    if [ ! -f "$data_file" ]; then
        return 1
    fi
    
    yq eval ".auto_discovery_preferences[]" "$data_file" 2>/dev/null
}

# Get CI runner specifications
get_ci_runner_specs() {
    local runner_type=$1
    local data_file="$SCRIPT_DIR/data/ci-environments.yaml"
    
    if [ ! -f "$data_file" ]; then
        return 1
    fi
    
    # Try to get the specific runner specs
    yq eval ".github_actions.runner_specs.\"$runner_type\"" "$data_file" 2>/dev/null
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

# Get failure classification by pattern matching
get_failure_classification() {
    local failure_reason="$1"
    local data_file="$SCRIPT_DIR/data/failure-classification.yaml"
    
    if [ ! -f "$data_file" ]; then
        echo "unknown" "permanent" "unknown_error" ""
        return 0
    fi
    
    # Loop through each failure category to find a match
    local categories=$(yq eval '.failure_categories | keys | .[]' "$data_file" 2>/dev/null)
    
    for category in $categories; do
        local patterns=$(yq eval ".failure_categories.\"$category\".patterns[]" "$data_file" 2>/dev/null)
        
        for pattern in $patterns; do
            # Remove parentheses and quotes from pattern for grep
            local clean_pattern=$(echo "$pattern" | sed 's/[)(]//g' | sed 's/"//g')
            
            if echo "$failure_reason" | grep -qiE "$clean_pattern"; then
                local failure_type=$(yq eval ".failure_categories.\"$category\".failure_type" "$data_file" 2>/dev/null)
                local category_enhanced=$(yq eval ".failure_categories.\"$category\".category_enhanced" "$data_file" 2>/dev/null)
                
                # Get remediation suggestions
                local remediation=$(yq eval ".failure_categories.\"$category\".remediation_suggestions[]" "$data_file" 2>/dev/null | sed ':a;N;$!ba;s/\n/\\n/g')
                
                echo "$category" "$failure_type" "$category_enhanced" "$remediation"
                return 0
            fi
        done
    done
    
    # Return unknown if no match found
    echo "unknown" "permanent" "unknown_error" "1. Check complete build logs\n2. Reproduce error locally\n3. Search for similar issues online\n4. Check upstream documentation\n5. Report bug with full logs"
}

# Get valid distributions
get_valid_distributions() {
    local data_file="$SCRIPT_DIR/data/distributions.yaml"
    
    if [ ! -f "$data_file" ]; then
        return 1
    fi
    
    yq eval ".distributions.valid[]" "$data_file" 2>/dev/null
}

# Check if architecture is supported for a distribution
is_arch_supported_for_dist_from_yaml() {
    local arch=$1
    local dist=$2
    local data_file="$SCRIPT_DIR/data/architecture-support.yaml"
    
    if [ ! -f "$data_file" ]; then
        # Default to true if data file not available
        return 0
    fi
    
    # Get supported distributions for this architecture
    local supported_dists=$(get_supported_distributions_for_arch "$arch")
    
    if [ -n "$supported_dists" ]; then
        # Check if the requested distribution is in the supported list
        echo "$supported_dists" | grep -q "^${dist}$"
        return $?
    else
        # If no specific restrictions, assume supported
        return 0
    fi
}