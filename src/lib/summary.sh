#!/bin/bash

# Build summary generation functions

# Function to generate build summary JSON
generate_build_summary() {
    local build_end_time=$(date +%s)
    local build_duration=$((build_end_time - BUILD_START_TIME))

    # Get list of built packages with their sizes
    local packages_json="["
    local first=true
    local total_size=0
    for pkg in ${PACKAGE_NAME}_*.deb; do
        if [ -f "$pkg" ]; then
            local size=$(stat -f%z "$pkg" 2>/dev/null || stat -c%s "$pkg" 2>/dev/null || echo "0")
            total_size=$((total_size + size))
            if [ "$first" = true ]; then
                first=false
            else
                packages_json+=","
            fi
            packages_json+="{\"name\":\"$pkg\",\"size\":$size}"
        fi
    done
    packages_json+="]"

    # Get architectures and distributions as JSON arrays
    local archs_json=$(echo "$ARCHITECTURES" | tr ' ' '\n' | jq -R -s 'split("\n") | map(select(length > 0))')
    local dists_json=$(echo "$DISTRIBUTIONS" | tr ' ' '\n' | jq -R -s 'split("\n") | map(select(length > 0))')

    # Convert total size to human-readable format
    local size_mb=$((total_size / 1024 / 1024))
    local size_kb=$((total_size / 1024))
    local size_human
    if [ $size_mb -gt 0 ]; then
        size_human="${size_mb} MB"
    else
        size_human="${size_kb} KB"
    fi

    # Get lintian summary
    local lintian_json=$(generate_lintian_summary)

    # Generate build summary JSON
    cat > build-summary.json <<EOF
{
  "package": "$PACKAGE_NAME",
  "version": "$VERSION",
  "build_version": "$BUILD_VERSION",
  "full_version": "$VERSION-$BUILD_VERSION",
  "github_repo": "$GITHUB_REPO",
  "architectures": $archs_json,
  "distributions": $dists_json,
  "total_packages": $TOTAL_PACKAGES,
  "total_size_bytes": $total_size,
  "total_size_human": "$size_human",
  "build_duration_seconds": $build_duration,
  "build_start": "$(date -d @$BUILD_START_TIME '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -r $BUILD_START_TIME '+%Y-%m-%dT%H:%M:%S%z')",
  "build_end": "$(date '+%Y-%m-%dT%H:%M:%S%z')",
  "parallel_builds": $PARALLEL_BUILDS,
  "max_parallel": $MAX_PARALLEL,
  "packages": $packages_json,
  "lintian": $lintian_json
}
EOF

    success "Build summary saved to build-summary.json"
    echo "   📦 Total artifact size: $size_human ($TOTAL_PACKAGES packages)"
}
