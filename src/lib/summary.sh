#!/bin/bash

# Build summary generation functions

# Generate viral badge markdown
generate_viral_badge() {
    local success_rate="${1:-100}"
    local build_time="${2:-0}"
    
    cat << EOF

---
🚀 Built with **debian-multiarch-builder**
[![Built with debian-multiarch-builder](https://img.shields.io/badge/built%20with-debian--multiarch--builder-blue?logo=github)](https://github.com/ranjithrajv/debian-multiarch-builder)

**Build Stats:**
- ⚡ Success Rate: ${success_rate}%
- ⏱️  Build Time: ${build_time}s
- 📦 Packages: ${TOTAL_PACKAGES}
- 🏗️  Architectures: $(echo "$ARCHITECTURES" | wc -w | tr -d ' ')

→ Try it free: \`./build.sh --setup\` or \`./build.sh --zc owner/repo version 1\`
EOF
}

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

    # Get telemetry summary if available
    local telemetry_json=$(get_telemetry_summary 2>/dev/null || echo "{}")

    # Calculate success rate for badge
    local attempted_packages=0
    for arch in $(cat /tmp/attempted_architectures.txt 2>/dev/null); do
        local supported_count=0
        for dist in "bookworm" "trixie" "forky" "sid"; do
            if is_arch_supported_for_dist "$arch" "$dist" 2>/dev/null; then
                supported_count=$((supported_count + 1))
            fi
        done
        attempted_packages=$((attempted_packages + supported_count))
    done
    
    local success_rate=0
    if [ "$attempted_packages" -gt 0 ]; then
        success_rate=$(( (TOTAL_PACKAGES * 100) / attempted_packages ))
    fi

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
  "lintian": $lintian_json,
  "telemetry": $telemetry_json,
  "success_rate": $success_rate
}
EOF

    success "Build summary saved to build-summary.json"
    echo "   📦 Total artifact size: $size_human ($TOTAL_PACKAGES packages)"
    
    # Generate and display viral badge
    echo ""
    generate_viral_badge "$success_rate" "$build_duration"
}
