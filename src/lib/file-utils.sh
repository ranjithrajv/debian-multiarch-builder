#!/bin/bash

# File operations and YAML utilities

# File utilities
require_file() {
    local file="$1"
    local message="${2:-Required file not found: $file}"

    if [ ! -f "$file" ]; then
        error "$message"
    fi
}

ensure_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || error "Failed to create directory: $dir"
    fi
}

# Safe YAML query utilities
yq_safe_eval() {
    local query="$1"
    local file="$2"
    local default="${3:-}"

    if [ ! -f "$file" ]; then
        echo "$default"
        return 1
    fi

    local result=$(yq eval "$query" "$file" 2>/dev/null)
    if [ "$result" = "null" ] || [ -z "$result" ]; then
        echo "$default"
        return 1
    fi

    echo "$result"
}