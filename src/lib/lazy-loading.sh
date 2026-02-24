#!/bin/bash

# Lazy loading system for library modules

# Global associative arrays to track loaded libraries and functions
declare -A LOADED_LIBRARIES
declare -A LIBRARY_FUNCTIONS

# Initialize lazy loading system
init_lazy_loading() {
    local lib_dir="${SCRIPT_DIR}/lib"
    
    # Index all available libraries and their functions
    for lib_file in "$lib_dir"/*.sh; do
        if [ -f "$lib_file" ]; then
            local lib_name=$(basename "$lib_file" .sh)
            
            # Extract function names from library
            local functions=$(grep -E '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)' "$lib_file" | \
                           sed -E 's/^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(\).*/\1/' | \
                           grep -v '^init_' | grep -v '^_' | tr '\n' ' ')
            
            LIBRARY_FUNCTIONS[$lib_name]="$functions"
            LOADED_LIBRARIES[$lib_name]="false"
        fi
    done
}

# Lazy load a library when needed
lazy_load_library() {
    local lib_name="$1"
    
    # Check if library is already loaded
    if [ "${LOADED_LIBRARIES[$lib_name]:-false}" = "true" ]; then
        return 0
    fi
    
    # Load the library
    local lib_file="${SCRIPT_DIR}/lib/${lib_name}.sh"
    if [ -f "$lib_file" ]; then
        source "$lib_file"
        LOADED_LIBRARIES[$lib_name]="true"
        
        # Debug logging for library loading
        if [ "${DEBUG_LAZY_LOADING:-false}" = "true" ]; then
            echo "DEBUG: Loaded library $lib_name" >&2
        fi
        
        return 0
    else
        echo "Error: Library $lib_name not found at $lib_file" >&2
        return 1
    fi
}

# Create wrapper functions for lazy loading
create_lazy_wrapper() {
    local func_name="$1"
    local lib_name="$2"
    
    # Create a wrapper function that loads the library before calling the function
    eval "
    $func_name() {
        lazy_load_library '$lib_name'
        $func_name \"\$@\"
    }
    "
}

# Setup lazy wrappers for all functions
setup_lazy_wrappers() {
    for lib_name in "${!LIBRARY_FUNCTIONS[@]}"; do
        local functions="${LIBRARY_FUNCTIONS[$lib_name]}"
        
        for func_name in $functions; do
            # Skip if function already exists (core functions)
            if ! declare -f "$func_name" >/dev/null 2>&1; then
                create_lazy_wrapper "$func_name" "$lib_name"
            fi
        done
    done
}

# Essential libraries that should be loaded immediately
load_essential_libraries() {
    local essential_libs=(
        "logging"          # Required for all output
        "essential-utils"  # Core utilities
        "file-utils"       # File operations
    )
    
    for lib in "${essential_libs[@]}"; do
        lazy_load_library "$lib"
    done
}

# Optional libraries that can be loaded on demand
get_optional_libraries() {
    echo "config-simple discovery-simple build orchestration summary telemetry github-api validation download-cache resource-pool"
}

# Preload specific libraries based on feature flags
preload_feature_libraries() {
    # Load telemetry library if enabled
    if [ "${TELEMETRY_ENABLED:-false}" = "true" ]; then
        lazy_load_library "telemetry"
    fi
    
    # Load lintian library if enabled
    if [ "${LINTIAN_CHECK:-false}" = "true" ]; then
        lazy_load_library "lintian"
    fi
    
    # Load libraries based on operation mode
    case "${1:-build}" in
        "validate")
            lazy_load_library "validation"
            lazy_load_library "github-api"
            ;;
        "build")
            # Build libraries will be loaded as needed
            ;;
        "test")
            lazy_load_library "testing"
            ;;
    esac
}

# Show loading statistics (for debugging)
show_loading_stats() {
    if [ "${DEBUG_LAZY_LOADING:-false}" = "true" ]; then
        echo "=== Library Loading Statistics ===" >&2
        echo "Total libraries available: ${#LIBRARY_FUNCTIONS[@]}" >&2
        
        local loaded_count=0
        for lib_name in "${!LOADED_LIBRARIES[@]}"; do
            if [ "${LOADED_LIBRARIES[$lib_name]}" = "true" ]; then
                loaded_count=$((loaded_count + 1))
                echo "  ✓ $lib_name (loaded)" >&2
            else
                echo "  ✗ $lib_name (not loaded)" >&2
            fi
        done
        
        echo "Libraries loaded: $loaded_count/${#LOADED_LIBRARIES[@]}" >&2
        echo "================================" >&2
    fi
}

# Cleanup lazy loading system
cleanup_lazy_loading() {
    unset LOADED_LIBRARIES
    unset LIBRARY_FUNCTIONS
}

# Initialize the lazy loading system
if [ -n "$SCRIPT_DIR" ]; then
    init_lazy_loading
    setup_lazy_wrappers
    load_essential_libraries
    
    # Set up trap to show stats on exit if debug mode is enabled
    if [ "${DEBUG_LAZY_LOADING:-false}" = "true" ]; then
        trap 'show_loading_stats' EXIT
    fi
fi

# Export functions for use in other scripts
export -f lazy_load_library
export -f load_essential_libraries
export -f preload_feature_libraries
export -f show_loading_stats