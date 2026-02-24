#!/bin/bash

# Auto-Discovery Mode - Automatic configuration generation
# Allows building without a configuration file by auto-detecting from GitHub repo

_ZC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "$_ZC_LIB_DIR/logging.sh"

# Auto-detect GitHub repo from current directory
detect_github_repo() {
    local git_remote=$(git remote get-url origin 2>/dev/null || echo "")
    
    if [ -z "$git_remote" ]; then
        return 1
    fi
    
    # Extract owner/repo from git remote URL
    # Handles: https://github.com/owner/repo.git, git@github.com:owner/repo.git
    local repo=$(echo "$git_remote" | sed -E 's|.*github\.com[:/](.+?)(\.git)?$|\1|')
    
    if [ -n "$repo" ] && [[ "$repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
        echo "$repo"
        return 0
    fi
    
    return 1
}

# Fetch latest release version from GitHub
fetch_latest_release() {
    local repo="$1"
    local response=$(curl -s "https://api.github.com/repos/${repo}/releases/latest")
    local version=$(echo "$response" | jq -r '.tag_name // .name // empty' 2>/dev/null)
    
    if [ -n "$version" ] && [ "$version" != "null" ]; then
        echo "$version"
        return 0
    fi
    
    # Fallback: get latest tag
    local tags=$(curl -s "https://api.github.com/repos/${repo}/tags?per_page=1" | jq -r '.[0].name // empty' 2>/dev/null)
    if [ -n "$tags" ] && [ "$tags" != "null" ]; then
        echo "$tags"
        return 0
    fi
    
    return 1
}

# Auto-detect release pattern from GitHub releases
detect_release_pattern() {
    local repo="$1"
    local version="$2"
    
    # Fetch release assets
    local assets=$(curl -s "https://api.github.com/repos/${repo}/releases/tags/${version}" | jq -r '.assets[].name' 2>/dev/null)
    
    if [ -z "$assets" ]; then
        # Try latest release if version not found
        assets=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.assets[].name' 2>/dev/null)
    fi
    
    if [ -z "$assets" ]; then
        return 1
    fi
    
    # Analyze assets to detect pattern
    local linux_assets=$(echo "$assets" | grep -iE "linux.*\.(tar\.gz|tgz|zip)$" | head -5)
    
    if [ -z "$linux_assets" ]; then
        return 1
    fi
    
    # Detect architecture patterns
    local has_x86_64=$(echo "$linux_assets" | grep -ciE "x86_64|amd64|x64" || echo "0")
    local has_aarch64=$(echo "$linux_assets" | grep -ciE "aarch64|arm64|armv8" || echo "0")
    local has_armv7=$(echo "$linux_assets" | grep -ciE "armv7|armhf|armv7l" || echo "0")
    local has_i686=$(echo "$linux_assets" | grep -ciE "i686|i386|x86" || echo "0")
    
    # Detect naming pattern
    local sample_asset=$(echo "$linux_assets" | head -1)
    
    # Pattern: name_version_arch.ext (e.g., eza_v0.18.0_x86_64-unknown-linux-gnu.tar.gz)
    if echo "$sample_asset" | grep -qE ".*_v?\{version\}?_.*arch.*"; then
        echo "pattern:standard"
        return 0
    fi
    
    # Pattern: name-version-arch.ext (e.g., bat-v0.24.0-x86_64-unknown-linux-gnu.tar.gz)
    if echo "$sample_asset" | grep -qE ".*-v?\{version\}?-.*arch.*"; then
        echo "pattern:dash"
        return 0
    fi
    
    # Return detected info
    echo "has_x86_64:$has_x86_64,has_aarch64:$has_aarch64,has_armv7:$has_armv7,has_i686:$has_i686"
    return 0
}

# Generate architecture map based on detected assets
generate_architecture_map() {
    local repo="$1"
    local version="$2"
    
    local assets=$(curl -s "https://api.github.com/repos/${repo}/releases/tags/${version}" | jq -r '.assets[].name' 2>/dev/null)
    
    if [ -z "$assets" ]; then
        assets=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.assets[].name' 2>/dev/null)
    fi
    
    local linux_assets=$(echo "$assets" | grep -iE "linux.*\.(tar\.gz|tgz|zip)$")
    
    if [ -z "$linux_assets" ]; then
        return 1
    fi
    
    local arch_map=""
    
    # Detect amd64/x86_64
    if echo "$linux_assets" | grep -qiE "x86_64|amd64"; then
        local detected=$(echo "$linux_assets" | grep -oiE "x86_64|amd64" | head -1)
        arch_map="${arch_map}  amd64: \"${detected}\"\n"
    fi
    
    # Detect arm64/aarch64
    if echo "$linux_assets" | grep -qiE "aarch64|arm64"; then
        local detected=$(echo "$linux_assets" | grep -oiE "aarch64|arm64" | head -1)
        arch_map="${arch_map}  arm64: \"${detected}\"\n"
    fi
    
    # Detect armhf/armv7
    if echo "$linux_assets" | grep -qiE "armv7|armhf|armv7l"; then
        local detected=$(echo "$linux_assets" | grep -oiE "armv7|armhf|armv7l" | head -1)
        arch_map="${arch_map}  armhf: \"${detected}\"\n"
    fi
    
    # Detect i386/i686
    if echo "$linux_assets" | grep -qiE "i686|i386"; then
        local detected=$(echo "$linux_assets" | grep -oiE "i686|i386" | head -1)
        arch_map="${arch_map}  i386: \"${detected}\"\n"
    fi
    
    if [ -n "$arch_map" ]; then
        echo -e "$arch_map"
        return 0
    fi
    
    return 1
}

# Detect download pattern format
detect_pattern_format() {
    local repo="$1"
    local version="$2"
    
    local assets=$(curl -s "https://api.github.com/repos/${repo}/releases/tags/${version}" | jq -r '.assets[].name' 2>/dev/null)
    
    if [ -z "$assets" ]; then
        assets=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.assets[].name' 2>/dev/null)
    fi
    
    local linux_asset=$(echo "$assets" | grep -iE "linux.*x86_64.*\.(tar\.gz|tgz|zip)$" | head -1)
    
    if [ -z "$linux_asset" ]; then
        linux_asset=$(echo "$assets" | grep -iE "linux.*\.(tar\.gz|tgz|zip)$" | head -1)
    fi
    
    if [ -z "$linux_asset" ]; then
        return 1
    fi
    
    # Analyze pattern - check if version is in filename or just in release tag
    local version_pattern=$(echo "$linux_asset" | grep -oE "v?[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    
    if [ -n "$version_pattern" ]; then
        # Version is in filename - use standard pattern detection
        local pattern_with_version="${linux_asset//$version_pattern/\{version\}}"
        local pattern=$(echo "$pattern_with_version" | sed -E 's/(x86_64|amd64|aarch64|arm64|armv7|armhf|i686|i386)/{arch}/i')
        echo "$pattern"
    else
        # Version is NOT in filename (it's only in release tag)
        # Pattern is like: eza_{arch}-unknown-linux-gnu.tar.gz
        local pattern=$(echo "$linux_asset" | sed -E 's/(x86_64|amd64|aarch64|arm64|armv7|armhf|i686|i386)/{arch}/i')
        echo "$pattern"
    fi
    
    return 0
}

# Generate configuration from auto-discovery
generate_config() {
    local repo="$1"
    local version="$2"
    local output_file="$3"
    
    echo "🔍 Auto-discovering configuration for $repo..."
    echo ""
    
    # Get package name from repo
    local package_name=$(basename "$repo")
    
    # Fetch latest release if version not provided
    if [ -z "$version" ]; then
        version=$(fetch_latest_release "$repo")
        if [ -z "$version" ]; then
            error_no_exit "Could not detect latest version for $repo"
            return 1
        fi
        info "Detected latest version: $version"
    fi
    
    # Detect download pattern
    local download_pattern=$(detect_pattern_format "$repo" "$version")
    if [ -z "$download_pattern" ]; then
        error_no_exit "Could not auto-detect download pattern"
        info "The project may not publish pre-built Linux binaries"
        return 1
    fi
    info "Detected download pattern: $download_pattern"
    
    # Generate architecture map
    local arch_map=$(generate_architecture_map "$repo" "$version")
    if [ -n "$arch_map" ]; then
        info "Detected architectures:"
        echo "$arch_map" | sed 's/^/   /'
    fi
    
    # Get repo description for summary
    local description=$(curl -s "https://api.github.com/repos/${repo}" | jq -r '.description // empty' 2>/dev/null)
    local license=$(curl -s "https://api.github.com/repos/${repo}" | jq -r '.license.spdx_id // "Unknown"' 2>/dev/null)
    
    # Generate YAML configuration
    cat > "$output_file" << EOF
# Auto-generated configuration for $repo
# Generated on: $(date -Iseconds)
# 
# Review and customize this configuration as needed.
# See docs/configuration-reference.md for all options.

package_name: "$package_name"
github_repo: "$repo"
summary: "$description"
license: "$license"

# Auto-detected download pattern
download_pattern: "$download_pattern"

# Auto-detected architecture mapping
architecture_map:
$arch_map
# Optional: Uncomment to enable
# parallel_builds: true
# max_parallel: 2
EOF

    success "Configuration generated: $output_file"
    echo ""
    echo "Next steps:"
    echo "  1. Review the generated configuration"
    echo "  2. Customize if needed (add dependencies, adjust patterns)"
    echo "  3. Run: ./build.sh $output_file $version 1"
    echo ""
    
    return 0
}

# Interactive setup wizard
run_setup_wizard() {
    echo "=========================================="
    echo "🔧 Debian Multi-Arch Builder Setup Wizard"
    echo "=========================================="
    echo ""
    echo "This wizard will help you create a configuration file."
    echo "It will auto-detect settings from your GitHub repository."
    echo ""
    
    # Check if in git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        warning "Not in a git repository. Auto-detection will be limited."
        echo ""
    fi
    
    # Step 1: Get GitHub repo
    local detected_repo=$(detect_github_repo)
    
    echo "📋 Step 1/3: GitHub Repository"
    echo ""
    
    if [ -n "$detected_repo" ]; then
        echo "Detected from git remote: $detected_repo"
        read -p "Use this repository? [Y/n]: " use_detected
        if [[ "$use_detected" =~ ^[Yy]$ ]] || [ -z "$use_detected" ]; then
            GITHUB_REPO="$detected_repo"
        else
            read -p "Enter GitHub repository (owner/repo): " GITHUB_REPO
        fi
    else
        read -p "Enter GitHub repository (owner/repo): " GITHUB_REPO
    fi
    
    # Validate repo format
    if [[ ! "$GITHUB_REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid repository format. Expected: owner/repo"
    fi
    
    echo ""
    
    # Step 2: Get version
    echo "📋 Step 2/3: Version"
    echo ""
    
    local latest_version=$(fetch_latest_release "$GITHUB_REPO")
    
    if [ -n "$latest_version" ]; then
        echo "Latest release: $latest_version"
        read -p "Build this version? [Y/n]: " use_latest
        if [[ "$use_latest" =~ ^[Yy]$ ]] || [ -z "$use_latest" ]; then
            VERSION="$latest_version"
        else
            read -p "Enter version to build: " VERSION
        fi
    else
        read -p "Enter version to build: " VERSION
    fi
    
    echo ""
    
    # Step 3: Output file
    echo "📋 Step 3/3: Configuration File"
    echo ""
    
    local default_config=".github/build-config.yaml"
    echo "Default output: $default_config"
    read -p "Use this location? [Y/n]: " use_default
    if [[ "$use_default" =~ ^[Yy]$ ]] || [ -z "$use_default" ]; then
        OUTPUT_FILE="$default_config"
    else
        read -p "Enter output file path: " OUTPUT_FILE
    fi
    
    # Create directory if needed
    local output_dir=$(dirname "$OUTPUT_FILE")
    if [ "$output_dir" != "." ] && [ ! -d "$output_dir" ]; then
        mkdir -p "$output_dir"
        info "Created directory: $output_dir"
    fi
    
    echo ""
    echo "=========================================="
    echo "Generating Configuration..."
    echo "=========================================="
    echo ""
    
    # Generate configuration
    if generate_config "$GITHUB_REPO" "$VERSION" "$OUTPUT_FILE"; then
        success "Setup complete!"
        echo ""
        echo "To build your package:"
        echo "  ./build.sh $OUTPUT_FILE $VERSION 1"
        echo ""
        echo "To validate before building:"
        echo "  ./build.sh $OUTPUT_FILE $VERSION 1 --dry-run"
        echo ""
        return 0
    else
        error "Failed to generate configuration"
    fi
}

# Zero-config build - build without config file
zero_config_build() {
    local repo="$1"
    local version="$2"
    local build_version="$3"
    local target_arch="${4:-all}"
    
    echo "=========================================="
    echo "🚀 Auto-Discovery Build Mode"
    echo "=========================================="
    echo ""
    
    # Create temporary config
    local temp_config="/tmp/zeroconfig_${repo//\//_}.yaml"
    
    info "Auto-generating temporary configuration..."
    
    if ! generate_config "$repo" "$version" "$temp_config" > /dev/null 2>&1; then
        error "Failed to auto-detect configuration for $repo"
        echo ""
        echo "This project may not publish pre-built Linux binaries."
        echo "Please create a manual configuration file."
        return 1
    fi
    
    # Display the generated config
    echo ""
    echo "=========================================="
    echo "📋 Generated Configuration"
    echo "=========================================="
    echo ""
    cat "$temp_config"
    echo ""
    
    # Provide instructions
    echo "=========================================="
    echo "💡 Next Steps"
    echo "=========================================="
    echo ""
    echo "Configuration saved to: $temp_config"
    echo ""
    echo "To build now, run:"
    echo "  ./build.sh $temp_config $version $build_version"
    echo ""
    echo "To save this config to your repository:"
    echo "  cp $temp_config .github/build-config.yaml"
    echo "  git add .github/build-config.yaml"
    echo "  git commit -m 'Add build configuration for $repo'"
    echo ""
    echo "To validate before building:"
    echo "  ./build.sh $temp_config $version $build_version --dry-run"
    echo ""
    
    # Cleanup
    rm -f "$temp_config"
    
    return 0
}

# Export functions
export -f detect_github_repo
export -f fetch_latest_release
export -f detect_release_pattern
export -f generate_architecture_map
export -f detect_pattern_format
export -f generate_config
export -f run_setup_wizard
export -f zero_config_build
