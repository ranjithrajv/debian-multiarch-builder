#!/bin/bash

# Dry-run mode for instant validation
# Provides configuration validation and release availability checking without building

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source required libraries
source "$LIB_DIR/logging.sh"

# Dry run validation function
run_dry_run() {
    local config_file="$1"
    local version="$2"
    local build_version="$3"
    local target_arch="$4"
    
    # Filter out any flags from target_arch
    if [[ "$target_arch" == --* ]]; then
        target_arch="all"
    fi

    echo "=========================================="
    echo "🔍 DRY RUN MODE - Validation Only"
    echo "=========================================="
    echo ""

    local has_errors=false
    local warnings_count=0
    local errors_count=0

    # Step 1: Validate configuration file exists
    echo "📋 Step 1/5: Validating configuration file..."
    if [ ! -f "$config_file" ]; then
        error "❌ Configuration file not found: $config_file"
        echo ""
        echo "💡 Solutions:"
        echo "   1. Check the file path is correct"
        echo "   2. Create a configuration file (see docs/configuration-reference.md)"
        echo "   3. Use --template to generate a config from example"
        echo ""
        exit 1
    fi
    success "Configuration file found: $config_file"
    echo ""

    # Step 2: Validate YAML syntax and parse configuration
    echo "📋 Step 2/5: Parsing configuration..."
    if ! command -v yq &> /dev/null; then
        error "yq is not installed. Please install yq: https://github.com/mikefarah/yq"
    fi

    if ! yq eval '.' "$config_file" &> /dev/null; then
        error "Invalid YAML syntax in $config_file"
    fi

    # Extract key configuration values
    local package_name=$(yq eval '.package_name' "$config_file")
    local github_repo=$(yq eval '.github_repo' "$config_file")
    local download_pattern=$(yq eval '.download_pattern // ""' "$config_file")
    local artifact_format=$(yq eval '.artifact_format // "tar.gz"' "$config_file")

    # Validate required fields
    if [ "$package_name" = "null" ] || [ -z "$package_name" ]; then
        error "Missing required field 'package_name' in $config_file"
        has_errors=true
    else
        success "Package name: $package_name"
    fi

    if [ "$github_repo" = "null" ] || [ -z "$github_repo" ]; then
        error "Missing required field 'github_repo' in $config_file"
        has_errors=true
    else
        success "GitHub repo: $github_repo"
        
        # Validate repo format
        if [[ ! "$github_repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
            error "Invalid github_repo format: $github_repo (expected: owner/repo)"
            has_errors=true
        else
            success "Repo format: valid"
        fi
    fi

    if [ -n "$download_pattern" ] && [ "$download_pattern" != "null" ]; then
        success "Download pattern: $download_pattern"
        
        # Validate pattern has {version} placeholder
        if [[ ! "$download_pattern" =~ \{version\} ]]; then
            echo -e "${YELLOW}⚠️  WARNING: Download pattern doesn't contain {version} placeholder${NC}"
            warnings_count=$((warnings_count + 1))
        fi
        
        # Validate pattern has {arch} placeholder
        if [[ ! "$download_pattern" =~ \{arch\} ]]; then
            echo -e "${YELLOW}⚠️  WARNING: Download pattern doesn't contain {arch} placeholder${NC}"
            echo "   This may limit multi-architecture support"
            warnings_count=$((warnings_count + 1))
        fi
    else
        info "Download pattern: Will use auto-discovery"
    fi

    success "Artifact format: $artifact_format"
    success "YAML syntax: valid"
    echo ""

    # Step 3: Validate version exists
    echo "📋 Step 3/5: Checking version availability..."
    local release_url="https://api.github.com/repos/${github_repo}/releases/tags/${version}"
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "$release_url")

    if [ "$http_code" = "200" ]; then
        success "Version $version exists"
        
        # Get release date
        local release_date=$(curl -s "$release_url" | jq -r '.published_at // "unknown"' 2>/dev/null)
        if [ "$release_date" != "null" ] && [ -n "$release_date" ]; then
            info "Published: $release_date"
        fi
    elif [ "$http_code" = "404" ]; then
        error "Version $version not found for $github_repo"
        has_errors=true
        echo ""
        echo "💡 Solutions:"
        echo "   1. Check version number is correct (try: $version without 'v' prefix)"
        echo "   2. Verify the repository exists: https://github.com/$github_repo"
        echo "   3. Check available releases: https://github.com/$github_repo/releases"
        echo ""
        
        # Try to suggest similar versions
        echo "🔍 Fetching available versions..."
        local releases_response=$(curl -s "https://api.github.com/repos/${github_repo}/releases?per_page=10")
        local available_versions=$(echo "$releases_response" | jq -r '.[].tag_name' 2>/dev/null | head -5)
        
        if [ -n "$available_versions" ]; then
            echo ""
            echo "Recent releases:"
            echo "$available_versions" | while read -r ver; do
                echo "   - $ver"
            done
        fi
    elif [ "$http_code" = "403" ]; then
        warning "GitHub API rate limit reached. Cannot verify version."
        warnings_count=$((warnings_count + 1))
        echo "   Will attempt build anyway - may fail if version doesn't exist"
    else
        error "Failed to check version (HTTP $http_code)"
        has_errors=true
    fi
    echo ""

    # Step 4: Check release assets for target architectures
    echo "📋 Step 4/5: Checking release assets..."
    local assets_url="https://api.github.com/repos/${github_repo}/releases/tags/${version}"
    local release_assets=$(curl -s "$assets_url" | jq -r '.assets[].name' 2>/dev/null)

    if [ -z "$release_assets" ]; then
        warning "No release assets found for version $version"
        warnings_count=$((warnings_count + 1))
    else
        success "Found $(echo "$release_assets" | wc -l | tr -d ' ') release assets"
        echo ""
        
        # Determine architectures to check
        local check_archs=()
        if [ "$target_arch" = "all" ]; then
            check_archs=("amd64" "arm64" "armhf" "armel" "i386" "ppc64el" "s390x" "riscv64" "loong64")
        else
            check_archs=("$target_arch")
        fi

        # Map Debian arch names to common release arch names
        declare -A arch_map
        arch_map["amd64"]="x86_64|amd64|x86-64"
        arch_map["arm64"]="aarch64|arm64|armv8"
        arch_map["armhf"]="armhf|armv7|arm-7"
        arch_map["armel"]="armel|armv6|arm-6"
        arch_map["i386"]="i386|i686|x86"
        arch_map["ppc64el"]="ppc64el|ppc64le|powerpc"
        arch_map["s390x"]="s390x|s390"
        arch_map["riscv64"]="riscv64|riscv"
        arch_map["loong64"]="loong64|loongarch"

        local found_count=0
        local missing_count=0

        for arch in "${check_archs[@]}"; do
            local patterns="${arch_map[$arch]}"
            local found=false
            
            # Check if any asset matches this architecture
            while IFS= read -r asset; do
                if echo "$asset" | grep -qiE "$patterns"; then
                    # Filter out checksums and source files
                    if ! echo "$asset" | grep -qiE "sha256|checksum|source|\.sig$"; then
                        found=true
                        break
                    fi
                fi
            done <<< "$release_assets"

            if [ "$found" = "true" ]; then
                success "$arch: Available"
                found_count=$((found_count + 1))
            else
                echo -e "${RED}✗${NC} $arch: Not available"
                missing_count=$((missing_count + 1))
            fi
        done

        echo ""
        info "Architecture availability: $found_count found, $missing_count not available"

        if [ $missing_count -eq ${#check_archs[@]} ] && [ ${#check_archs[@]} -gt 0 ]; then
            warning "No assets found for any requested architecture"
            warnings_count=$((warnings_count + 1))
            echo ""
            echo "💡 Possible issues:"
            echo "   1. Architecture names in release don't match expected patterns"
            echo "   2. This project doesn't publish pre-built binaries"
            echo "   3. Version $version has no assets yet"
            echo ""
            echo "Available assets:"
            echo "$release_assets" | head -10 | while read -r asset; do
                echo "   - $asset"
            done
            if [ $(echo "$release_assets" | wc -l) -gt 10 ]; then
                echo "   ... and $(echo "$release_assets" | wc -l) total"
            fi
        fi
    fi
    echo ""

    # Step 5: Estimate build time and cost
    echo "📋 Step 5/5: Estimating build resources..."
    
    # Count architectures to build
    local total_archs=${#check_archs[@]}
    if [ "$target_arch" = "all" ]; then
        total_archs=$found_count
        if [ $total_archs -eq 0 ]; then
            total_archs=${#check_archs[@]}
        fi
    fi

    # Estimate based on typical build times
    local avg_build_time_per_arch=60  # seconds
    local parallel_factor=1
    if [ $total_archs -gt 1 ]; then
        parallel_factor=2  # Assume 2x parallelism
    fi
    
    local estimated_time=$(( (total_archs * avg_build_time_per_arch) / parallel_factor ))
    local estimated_minutes=$((estimated_time / 60))
    local estimated_seconds=$((estimated_time % 60))

    # GitHub Actions pricing (as of 2026): $0.008/minute for Ubuntu
    local cost_per_minute="0.008"
    local estimated_cost=$(echo "scale=3; $estimated_minutes * $cost_per_minute" | bc 2>/dev/null || echo "0.00")
    
    # Sequential cost for comparison
    local sequential_time=$((total_archs * avg_build_time_per_arch))
    local sequential_minutes=$((sequential_time / 60))
    local sequential_cost=$(echo "scale=3; $sequential_minutes * $cost_per_minute" | bc 2>/dev/null || echo "0.00")
    
    local savings=$(echo "scale=2; 100 - ($estimated_cost / $sequential_cost * 100)" | bc 2>/dev/null || echo "0")
    if [ "$savings" = "NaN" ] || [ -z "$savings" ]; then
        savings="0"
    fi

    info "Estimated build time: ${estimated_minutes}m ${estimated_seconds}s (parallel)"
    info "Sequential time: ${sequential_minutes}m (for comparison)"
    info "Estimated cost: \$${estimated_cost} (GitHub Actions Ubuntu)"
    info "Estimated savings: ${savings}% vs. sequential"
    echo ""

    # Show configuration summary
    echo "=========================================="
    echo "📊 CONFIGURATION SUMMARY"
    echo "=========================================="
    echo ""
    echo "Package:        $package_name"
    echo "Version:        $version"
    echo "Build Version:  $build_version"
    echo "GitHub Repo:    $github_repo"
    echo "Artifact Format: $artifact_format"
    if [ -n "$download_pattern" ] && [ "$download_pattern" != "null" ]; then
        echo "Download Pattern: $download_pattern"
    else
        echo "Download Pattern: Auto-discovery"
    fi
    echo "Target Arch:    $target_arch"
    echo "Architectures:  $total_archs"
    echo ""

    # Final verdict
    echo "=========================================="
    echo "📋 DRY RUN RESULT"
    echo "=========================================="
    echo ""

    if [ "$has_errors" = "true" ]; then
        echo -e "${RED}❌ VALIDATION FAILED${NC}"
        echo ""
        echo "Found $errors_count error(s) and $warnings_count warning(s)"
        echo ""
        echo "Please fix the errors above before running the build."
        echo "Run with --help for usage information."
        return 1
    elif [ $warnings_count -gt 0 ]; then
        echo -e "${YELLOW}⚠️  VALIDATION PASSED WITH WARNINGS${NC}"
        echo ""
        echo "Found $warnings_count warning(s)"
        echo ""
        echo "Build should succeed, but review warnings above."
        echo "Run without --dry-run to start the build."
        return 0
    else
        echo -e "${GREEN}✅ VALIDATION PASSED${NC}"
        echo ""
        echo "Configuration is valid and version is available."
        echo ""
        echo "Ready to build! Run:"
        echo "  ./build.sh $config_file $version $build_version $target_arch"
        echo ""
        echo "Or with parallel builds:"
        echo "  MAX_PARALLEL=2 ./build.sh $config_file $version $build_version $target_arch"
        return 0
    fi
}

# Export function for use in other scripts
export -f run_dry_run
