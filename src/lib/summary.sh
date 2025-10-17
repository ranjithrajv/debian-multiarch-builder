#!/bin/bash

# Build summary generation functions

# Function to generate build summary JSON
generate_build_summary() {
    local build_end_time=$(date +%s)
    local build_duration=$((build_end_time - BUILD_START_TIME))

    # Get list of built packages with their sizes
    local packages_json="["
    local first=true
    for pkg in ${PACKAGE_NAME}_*.deb; do
        if [ -f "$pkg" ]; then
            local size=$(stat -f%z "$pkg" 2>/dev/null || stat -c%s "$pkg" 2>/dev/null || echo "0")
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
  "build_duration_seconds": $build_duration,
  "build_start": "$(date -d @$BUILD_START_TIME '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -r $BUILD_START_TIME '+%Y-%m-%dT%H:%M:%S%z')",
  "build_end": "$(date '+%Y-%m-%dT%H:%M:%S%z')",
  "parallel_builds": $PARALLEL_BUILDS,
  "max_parallel": $MAX_PARALLEL,
  "packages": $packages_json
}
EOF

    success "Build summary saved to build-summary.json"
}
