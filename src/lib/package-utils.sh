#!/bin/bash

# Package collection and analysis utilities

# Package collection utilities
collect_packages() {
    local pattern="${1:-${PACKAGE_NAME}_*.deb}"
    ls $pattern 2>/dev/null | tr '\n' ' ' || echo ""
}

count_packages() {
    local pattern="${1:-${PACKAGE_NAME}_*.deb}"
    ls $pattern 2>/dev/null | wc -l || echo "0"
}

show_package_list() {
    local pattern="${1:-${PACKAGE_NAME}_*.deb}"
    local packages=$(ls $pattern 2>/dev/null)
    if [ -n "$packages" ]; then
        echo "$packages" | awk '{print "  " $1 " (" $5 ")"}'
    fi
}

get_built_architectures() {
    local pattern="${1:-${PACKAGE_NAME}_*.deb}"
    ls $pattern 2>/dev/null | sed 's/.*+\([^_]*\)_\([^\.]*\)\.deb/\2/' | sort -u | tr '\n' ' ' | sed 's/ *$//'
}

get_built_distributions() {
    local pattern="${1:-${PACKAGE_NAME}_*.deb}"
    ls $pattern 2>/dev/null | sed 's/.*+\([^_]*\)_[^_]*\.deb/\1/' | sort -u | tr '\n' ' ' | sed 's/ *$//'
}