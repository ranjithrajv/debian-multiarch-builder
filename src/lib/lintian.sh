#!/bin/bash

# Lintian validation functions for Debian package quality checks

# Global variables for lintian results tracking
LINTIAN_RESULTS_DIR=".lintian-results"
LINTIAN_TOTAL_ERRORS=0
LINTIAN_TOTAL_WARNINGS=0
LINTIAN_TOTAL_INFO=0

# Initialize lintian results directory
init_lintian_results() {
    mkdir -p "$LINTIAN_RESULTS_DIR"
    LINTIAN_TOTAL_ERRORS=0
    LINTIAN_TOTAL_WARNINGS=0
    LINTIAN_TOTAL_INFO=0
}

# Check if lintian is installed
check_lintian_installed() {
    if ! command -v lintian &> /dev/null; then
        warning "Lintian is not installed. Skipping package validation."
        warning "Install with: sudo apt-get install -y lintian"
        return 1
    fi
    return 0
}

# Get lintian configuration from config
get_lintian_config() {
    local key=$1
    local default=$2

    # Check if lintian config exists in parsed config
    if [ -f "$SCRIPT_DIR/defaults.yaml" ]; then
        local value=$(yq eval ".lintian.$key // \"$default\"" "$SCRIPT_DIR/defaults.yaml" 2>/dev/null)
        echo "$value"
    else
        echo "$default"
    fi
}

# Run lintian check on a package
run_lintian_check() {
    local deb_file=$1
    local pkg_name=$(basename "$deb_file" .deb)

    # Check if lintian is enabled
    if [ "${LINTIAN_CHECK:-false}" != "true" ]; then
        return 0
    fi

    if ! check_lintian_installed; then
        return 0
    fi

    info "Running lintian on $pkg_name..."

    # Get configuration
    local pedantic=$(get_lintian_config "pedantic" "false")
    local suppress_tags=$(get_lintian_config "suppress_tags" "[]")

    # Build lintian command
    local lintian_cmd="lintian"

    # Add pedantic flag if enabled
    if [ "$pedantic" = "true" ]; then
        lintian_cmd="$lintian_cmd --pedantic"
    fi

    # Add info level to get all messages
    lintian_cmd="$lintian_cmd --info"

    # Add suppress tags if any
    if [ "$suppress_tags" != "[]" ] && [ -n "$suppress_tags" ]; then
        # Convert YAML array to comma-separated list
        local tags=$(echo "$suppress_tags" | yq eval '.[] | "--suppress-tags " + .' 2>/dev/null | tr '\n' ' ')
        if [ -n "$tags" ]; then
            lintian_cmd="$lintian_cmd $tags"
        fi
    fi

    # Run lintian and capture output
    local result_file="$LINTIAN_RESULTS_DIR/${pkg_name}.txt"
    local exit_code=0

    # Lintian exits with 0 only if no errors/warnings, so we need to capture output regardless
    set +e
    $lintian_cmd "$deb_file" > "$result_file" 2>&1
    exit_code=$?
    set -e

    # Parse and display results
    parse_lintian_output "$result_file" "$pkg_name"

    # Determine if build should fail
    if should_fail_build "$result_file"; then
        error "Lintian validation failed for $pkg_name"
        return 1
    fi

    return 0
}

# Parse lintian output and categorize by severity
parse_lintian_output() {
    local result_file=$1
    local pkg_name=$2

    if [ ! -f "$result_file" ]; then
        return 0
    fi

    # Count issues by severity
    local errors=$(grep -c "^E: " "$result_file" 2>/dev/null || echo "0")
    local warnings=$(grep -c "^W: " "$result_file" 2>/dev/null || echo "0")
    local info=$(grep -c "^I: " "$result_file" 2>/dev/null || echo "0")

    # Update global counters
    LINTIAN_TOTAL_ERRORS=$((LINTIAN_TOTAL_ERRORS + errors))
    LINTIAN_TOTAL_WARNINGS=$((LINTIAN_TOTAL_WARNINGS + warnings))
    LINTIAN_TOTAL_INFO=$((LINTIAN_TOTAL_INFO + info))

    # Save counts to separate file for summary generation
    cat > "$LINTIAN_RESULTS_DIR/${pkg_name}.counts" <<EOF
{
  "package": "$pkg_name",
  "errors": $errors,
  "warnings": $warnings,
  "info": $info
}
EOF

    # Get display level
    local display_level=$(get_lintian_config "display_level" "info")

    # Display results based on severity
    if [ $errors -gt 0 ]; then
        echo "   ❌ Lintian: $errors error(s), $warnings warning(s), $info info"
        if [ "$display_level" = "error" ] || [ "$display_level" = "warning" ] || [ "$display_level" = "info" ]; then
            grep "^E: " "$result_file" | while read line; do
                echo "      $line"
            done
        fi
    elif [ $warnings -gt 0 ]; then
        echo "   ⚠️  Lintian: $warnings warning(s), $info info"
        if [ "$display_level" = "warning" ] || [ "$display_level" = "info" ]; then
            grep "^W: " "$result_file" | while read line; do
                echo "      $line"
            done
        fi
    elif [ $info -gt 0 ]; then
        echo "   ℹ️  Lintian: $info informational message(s)"
        if [ "$display_level" = "info" ]; then
            grep "^I: " "$result_file" | while read line; do
                echo "      $line"
            done
        fi
    else
        echo "   ✅ Lintian: No issues found"
    fi
}

# Determine if build should fail based on lintian results
should_fail_build() {
    local result_file=$1

    # Get failure configuration
    local fail_on_errors=$(get_lintian_config "fail_on_errors" "true")
    local fail_on_warnings=$(get_lintian_config "fail_on_warnings" "false")

    # Check for errors
    if [ "$fail_on_errors" = "true" ]; then
        local errors=$(grep -c "^E: " "$result_file" 2>/dev/null || echo "0")
        if [ $errors -gt 0 ]; then
            return 0  # Should fail
        fi
    fi

    # Check for warnings
    if [ "$fail_on_warnings" = "true" ]; then
        local warnings=$(grep -c "^W: " "$result_file" 2>/dev/null || echo "0")
        if [ $warnings -gt 0 ]; then
            return 0  # Should fail
        fi
    fi

    return 1  # Should not fail
}

# Generate summary of all lintian results
generate_lintian_summary() {
    if [ "${LINTIAN_CHECK:-false}" != "true" ]; then
        echo "{}"
        return 0
    fi

    if [ ! -d "$LINTIAN_RESULTS_DIR" ]; then
        echo "{}"
        return 0
    fi

    # Collect all package results
    local packages_json="["
    local first=true

    for count_file in "$LINTIAN_RESULTS_DIR"/*.counts; do
        if [ -f "$count_file" ]; then
            if [ "$first" = true ]; then
                first=false
            else
                packages_json+=","
            fi
            packages_json+=$(cat "$count_file")
        fi
    done

    packages_json+="]"

    # Generate summary JSON
    cat <<EOF
{
  "enabled": true,
  "total_errors": $LINTIAN_TOTAL_ERRORS,
  "total_warnings": $LINTIAN_TOTAL_WARNINGS,
  "total_info": $LINTIAN_TOTAL_INFO,
  "packages": $packages_json
}
EOF
}

# Clean up lintian results directory
cleanup_lintian_results() {
    if [ -d "$LINTIAN_RESULTS_DIR" ]; then
        rm -rf "$LINTIAN_RESULTS_DIR"
    fi
}

# Display lintian summary at end of build
display_lintian_summary() {
    if [ "${LINTIAN_CHECK:-false}" != "true" ]; then
        return 0
    fi

    if [ ! -d "$LINTIAN_RESULTS_DIR" ] || [ $LINTIAN_TOTAL_ERRORS -eq 0 ] && [ $LINTIAN_TOTAL_WARNINGS -eq 0 ]; then
        return 0
    fi

    echo ""
    echo "=========================================="
    echo "📋 Lintian Summary"
    echo "=========================================="
    echo "   Errors:   $LINTIAN_TOTAL_ERRORS"
    echo "   Warnings: $LINTIAN_TOTAL_WARNINGS"
    echo "   Info:     $LINTIAN_TOTAL_INFO"
    echo ""

    if [ $LINTIAN_TOTAL_ERRORS -gt 0 ]; then
        echo "   Review the lintian output above for details."
        echo "   Common issues: missing dependencies, policy violations, permission errors"
    fi
    echo ""
}
