#!/bin/bash

# Architecture state tracking utilities

get_attempted_architectures() {
    local attempted_file="/tmp/attempted_architectures.txt"
    if [ -f "$attempted_file" ]; then
        cat "$attempted_file" 2>/dev/null
    fi
}

get_skipped_architectures() {
    local skipped_file="/tmp/skipped_architectures.txt"
    if [ -f "$skipped_file" ]; then
        cat "$skipped_file" 2>/dev/null
    fi
}

get_available_architectures() {
    local available_file="/tmp/available_architectures.txt"
    if [ -f "$available_file" ]; then
        cat "$available_file" 2>/dev/null
    fi
}

count_architectures() {
    local file="$1"
    if [ -f "$file" ]; then
        wc -l < "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}