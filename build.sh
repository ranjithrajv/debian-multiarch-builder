#!/bin/bash

set -e

CONFIG_FILE=$1
VERSION=$2
BUILD_VERSION=$3
ARCH=${4:-all}

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Error reporting function
error() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}" >&2
}

info() {
    echo -e "${BLUE}ℹ️  INFO: $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Usage validation
if [ -z "$CONFIG_FILE" ] || [ -z "$VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <config-file> <version> <build-version> [architecture]"
    echo ""
    echo "Arguments:"
    echo "  config-file     Path to multiarch-config.yaml"
    echo "  version         Version to build (e.g., 0.9.3)"
    echo "  build-version   Debian build version (e.g., 1)"
    echo "  architecture    Target architecture or 'all' (default: all)"
    echo ""
    echo "Examples:"
    echo "  $0 config.yaml 2.35.0 1 arm64    # Build for arm64 only"
    echo "  $0 config.yaml 2.35.0 1 all      # Build for all architectures"
    echo ""
    echo "Supported architectures: amd64, arm64, armel, armhf, i386, ppc64el, s390x, riscv64"
    exit 1
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    error "Configuration file not found: $CONFIG_FILE"
fi

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    error "yq is not installed. Please install yq: https://github.com/mikefarah/yq"
fi

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    error "Docker is not installed or not in PATH"
fi

if ! docker ps &> /dev/null; then
    error "Docker daemon is not running or you don't have permission to access it"
fi

# Validate YAML syntax
if ! yq eval '.' "$CONFIG_FILE" &> /dev/null; then
    error "Invalid YAML syntax in $CONFIG_FILE"
fi

# Parse and validate configuration
PACKAGE_NAME=$(yq eval '.package_name' "$CONFIG_FILE")
GITHUB_REPO=$(yq eval '.github_repo' "$CONFIG_FILE")
ARTIFACT_FORMAT=$(yq eval '.artifact_format // "tar.gz"' "$CONFIG_FILE")
BINARY_PATH=$(yq eval '.binary_path // ""' "$CONFIG_FILE")
PARALLEL_BUILDS=$(yq eval '.parallel_builds // true' "$CONFIG_FILE")
MAX_PARALLEL=$(yq eval '.max_parallel // 2' "$CONFIG_FILE")

# Validate required fields
if [ "$PACKAGE_NAME" = "null" ] || [ -z "$PACKAGE_NAME" ]; then
    error "Missing required field 'package_name' in $CONFIG_FILE"
fi

if [ "$GITHUB_REPO" = "null" ] || [ -z "$GITHUB_REPO" ]; then
    error "Missing required field 'github_repo' in $CONFIG_FILE"
fi

# Validate GitHub repo format
if [[ ! "$GITHUB_REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
    error "Invalid github_repo format: $GITHUB_REPO (expected: owner/repo)"
fi

# Get and validate distributions
DISTRIBUTIONS=$(yq eval '.debian_distributions[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ')
if [ -z "$DISTRIBUTIONS" ] || [ "$DISTRIBUTIONS" = "null" ]; then
    error "Missing or empty 'debian_distributions' in $CONFIG_FILE"
fi

# Validate distribution names
VALID_DISTS="bookworm trixie forky sid"
for dist in $DISTRIBUTIONS; do
    if ! echo "$VALID_DISTS" | grep -qw "$dist"; then
        warning "Unknown distribution: $dist (valid: $VALID_DISTS)"
    fi
done

# Validate artifact format
case "$ARTIFACT_FORMAT" in
    "tar.gz"|"tgz"|"zip")
        ;;
    *)
        error "Unsupported artifact_format: $ARTIFACT_FORMAT (supported: tar.gz, tgz, zip)"
        ;;
esac

# Check if any architectures are defined
ARCH_COUNT=$(yq eval '.architectures | length' "$CONFIG_FILE")
if [ "$ARCH_COUNT" = "0" ] || [ "$ARCH_COUNT" = "null" ]; then
    error "No architectures defined in $CONFIG_FILE"
fi

# Detect architecture configuration mode (list vs object)
ARCH_TYPE=$(yq eval '.architectures | type' "$CONFIG_FILE")
if [ "$ARCH_TYPE" = "!!seq" ]; then
    AUTO_DISCOVERY=true
    info "Auto-discovery mode enabled (architectures specified as list)"
elif [ "$ARCH_TYPE" = "!!map" ]; then
    AUTO_DISCOVERY=false
    info "Manual mode (architectures with release_pattern)"
else
    error "Invalid architectures format in $CONFIG_FILE (must be list or object)"
fi

# Record build start time
BUILD_START_TIME=$(date +%s)

info "Building $PACKAGE_NAME version $VERSION"
info "GitHub repo: $GITHUB_REPO"
info "Distributions: $DISTRIBUTIONS"
info "Architectures defined: $ARCH_COUNT"
echo ""

# Architecture pattern mappings for auto-discovery
# Maps Debian arch to common upstream naming patterns
declare -A ARCH_PATTERNS=(
    ["amd64"]="x86_64|amd64|x64"
    ["arm64"]="aarch64|arm64"
    ["armel"]="arm-|armeabi"
    ["armhf"]="armv7|armhf|arm-.*gnueabihf"
    ["i386"]="i686|i386|x86"
    ["ppc64el"]="powerpc64le|ppc64le"
    ["s390x"]="s390x"
    ["riscv64"]="riscv64gc|riscv64"
)

# Cache for GitHub API release assets
RELEASE_ASSETS_CACHE=""

# Function to fetch release assets from GitHub API
fetch_release_assets() {
    # Return cached result if available
    if [ -n "$RELEASE_ASSETS_CACHE" ]; then
        echo "$RELEASE_ASSETS_CACHE"
        return 0
    fi

    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${VERSION}"
    info "Fetching release assets from GitHub API..."

    local assets=$(curl -sL "$api_url" | jq -r '.assets[]? | .name' 2>/dev/null)

    if [ -z "$assets" ]; then
        error "Failed to fetch release assets from $api_url

Possible reasons:
  - Version '$VERSION' doesn't exist for $GITHUB_REPO
  - GitHub API rate limit exceeded
  - Network connectivity issues

Please check: https://github.com/${GITHUB_REPO}/releases/tag/${VERSION}"
    fi

    # Cache the result
    RELEASE_ASSETS_CACHE="$assets"
    echo "$assets"
}

# Function to auto-discover release pattern for an architecture
auto_discover_pattern() {
    local arch=$1
    local pattern="${ARCH_PATTERNS[$arch]}"

    if [ -z "$pattern" ]; then
        return 1
    fi

    # Fetch all release assets
    local assets=$(fetch_release_assets)

    # Filter assets by format and pattern, filter out checksums and source
    local filtered_assets=$(echo "$assets" | \
        grep -E "\.(${ARTIFACT_FORMAT}|tgz|tar\.gz|zip)$" | \
        grep -v -i "sha256\|checksum\|source" | \
        grep -iE "$pattern" | \
        grep -i "linux")

    # Prefer gnu builds (better for Debian), then musl builds, then any linux build
    local matched_asset=$(echo "$filtered_assets" | grep -i "gnu" | head -1)
    if [ -z "$matched_asset" ]; then
        matched_asset=$(echo "$filtered_assets" | grep -i "musl" | head -1)
    fi
    if [ -z "$matched_asset" ]; then
        matched_asset=$(echo "$filtered_assets" | head -1)
    fi

    if [ -z "$matched_asset" ]; then
        return 1
    fi

    echo "$matched_asset"
    return 0
}

# Function to get release pattern for an architecture
get_release_pattern() {
    local arch=$1

    if [ "$AUTO_DISCOVERY" = "true" ]; then
        # Auto-discovery mode
        local pattern=$(auto_discover_pattern "$arch")
        if [ $? -ne 0 ] || [ -z "$pattern" ]; then
            return 1
        fi
        echo "$pattern"
        return 0
    else
        # Manual mode
        local pattern=$(yq eval ".architectures.${arch}.release_pattern" "$CONFIG_FILE")

        if [ "$pattern" = "null" ] || [ -z "$pattern" ]; then
            return 1
        fi

        # Validate pattern has {version} placeholder
        if [[ ! "$pattern" =~ \{version\} ]]; then
            warning "Release pattern for $arch doesn't contain {version} placeholder: $pattern"
        fi

        # Replace {version} placeholder with actual version
        pattern="${pattern//\{version\}/$VERSION}"
        echo "$pattern"
        return 0
    fi
}

# Function to get all supported architectures from config
get_supported_architectures() {
    if [ "$AUTO_DISCOVERY" = "true" ]; then
        # List format: architectures are array items
        yq eval '.architectures[]' "$CONFIG_FILE"
    else
        # Object format: architectures are keys
        yq eval '.architectures | keys | .[]' "$CONFIG_FILE"
    fi
}

# Function to check if architecture is supported for a distribution
is_arch_supported_for_dist() {
    local arch=$1
    local dist=$2

    # Check if there's a distribution override
    local override_dists=$(yq eval ".distribution_arch_overrides.${arch}.distributions[]" "$CONFIG_FILE" 2>/dev/null)

    if [ "$override_dists" != "null" ] && [ -n "$override_dists" ]; then
        # If override exists, check if dist is in the list
        echo "$override_dists" | grep -q "^${dist}$"
        return $?
    fi

    # No override, all distributions supported
    return 0
}

# Function to validate upstream release exists
validate_release() {
    local url=$1
    info "Validating upstream release: $url"

    # Use HEAD request to check if release exists
    if ! wget --spider -q "$url" 2>&1; then
        return 1
    fi
    return 0
}

# Function to verify checksum of downloaded file
verify_checksum() {
    local archive_name=$1
    local release_pattern=$2

    # Try to find checksum file in release assets
    local assets=$(fetch_release_assets)

    # Look for common checksum file patterns
    local checksum_file=""
    for pattern in "${release_pattern}.sha256" "${release_pattern}.sha256sum" "SHA256SUMS" "checksums.txt"; do
        if echo "$assets" | grep -qi "^${pattern}$"; then
            checksum_file="$pattern"
            break
        fi
    done

    # Also try generic patterns that might contain our file
    if [ -z "$checksum_file" ]; then
        for pattern in "sha256" "checksums" "sums"; do
            local found=$(echo "$assets" | grep -i "$pattern" | grep -v "sig$" | head -1)
            if [ -n "$found" ]; then
                checksum_file="$found"
                break
            fi
        done
    fi

    if [ -z "$checksum_file" ]; then
        info "No checksum file found for verification (optional)"
        return 0
    fi

    # Download checksum file
    local checksum_url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${checksum_file}"
    info "Found checksum file: $checksum_file"

    if ! wget -q "$checksum_url" 2>&1; then
        warning "Failed to download checksum file, skipping verification"
        return 0
    fi

    # Extract the checksum for our specific file
    local expected_checksum=""
    if grep -q "$archive_name" "$checksum_file" 2>/dev/null; then
        expected_checksum=$(grep "$archive_name" "$checksum_file" | awk '{print $1}')
    elif [ -f "$checksum_file" ] && [ $(wc -l < "$checksum_file") -eq 1 ]; then
        # Single checksum file for single archive
        expected_checksum=$(awk '{print $1}' "$checksum_file")
    fi

    if [ -z "$expected_checksum" ]; then
        warning "Could not find checksum for $archive_name in $checksum_file"
        rm -f "$checksum_file"
        return 0
    fi

    # Calculate actual checksum
    info "Verifying checksum..."
    local actual_checksum=$(sha256sum "$archive_name" | awk '{print $1}')

    # Compare checksums
    if [ "$expected_checksum" = "$actual_checksum" ]; then
        success "Checksum verified: $archive_name"
        rm -f "$checksum_file"
        return 0
    else
        rm -f "$checksum_file"
        error "Checksum verification failed for $archive_name

Expected: $expected_checksum
Actual:   $actual_checksum

The downloaded file may be corrupted or tampered with."
    fi
}

# Function to build a package for a specific distribution
build_distribution() {
    local build_arch=$1
    local dist=$2
    local binary_source=$3

    FULL_VERSION="${VERSION}-${BUILD_VERSION}+${dist}_${build_arch}"

    if ! docker build . -t "${PACKAGE_NAME}-${dist}-${build_arch}" \
        --build-arg DEBIAN_DIST="$dist" \
        --build-arg PACKAGE_NAME="$PACKAGE_NAME" \
        --build-arg VERSION="$VERSION" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$FULL_VERSION" \
        --build-arg ARCH="$build_arch" \
        --build-arg BINARY_SOURCE="$binary_source" \
        --build-arg GITHUB_REPO="$GITHUB_REPO" 2>&1; then
        return 1
    fi

    id="$(docker create "${PACKAGE_NAME}-${dist}-${build_arch}")"
    if ! docker cp "$id:/${PACKAGE_NAME}_${FULL_VERSION}.deb" - > "./${PACKAGE_NAME}_${FULL_VERSION}.deb" 2>&1; then
        docker rm "$id" || true
        return 1
    fi

    docker rm "$id" || true

    if ! tar -xf "./${PACKAGE_NAME}_${FULL_VERSION}.deb" 2>&1; then
        return 1
    fi

    return 0
}

# Function to build for a specific architecture
build_architecture() {
    local build_arch=$1
    local release_pattern

    release_pattern=$(get_release_pattern "$build_arch")
    if [ $? -ne 0 ]; then
        error "Architecture '$build_arch' not found in config or has no release_pattern"
    fi

    echo "==========================================="
    info "Building for architecture: $build_arch"
    info "Release pattern: $release_pattern"
    echo "==========================================="

    # Extract filename without extension for directory name
    local archive_name="${release_pattern}"
    local extract_dir="${archive_name%.tar.gz}"
    extract_dir="${extract_dir%.zip}"
    extract_dir="${extract_dir%.tgz}"

    # Clean up any previous builds for this architecture
    if [ -d "$extract_dir" ] || [ -f "$archive_name" ]; then
        info "Cleaning up previous build artifacts..."
        rm -rf "$extract_dir" || true
        rm -f "$archive_name" || true
    fi

    # Download the release artifact (ONCE for all distributions)
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${release_pattern}"
    info "Downloading from: $download_url"

    # Validate release exists before downloading
    if ! validate_release "$download_url"; then
        error "Release not found: $download_url

Possible reasons:
  - Version '$VERSION' doesn't exist for $GITHUB_REPO
  - Release pattern is incorrect: $release_pattern
  - Architecture '$build_arch' is not published by upstream

Please check:
  1. https://github.com/${GITHUB_REPO}/releases/tag/${VERSION}
  2. Verify the release_pattern in your config matches actual release assets"
    fi

    if ! wget -q --show-progress "$download_url" 2>&1; then
        error "Failed to download release for $build_arch from $download_url"
    fi

    success "Downloaded $archive_name"

    # Verify checksum if available
    verify_checksum "$archive_name" "$release_pattern"

    # Extract the archive based on format (ONCE for all distributions)
    info "Extracting $archive_name..."
    case "$ARTIFACT_FORMAT" in
        "tar.gz"|"tgz")
            if ! tar -xzf "$archive_name" 2>&1; then
                error "Failed to extract $archive_name (corrupted archive?)"
            fi
            ;;
        "zip")
            if ! unzip -q "$archive_name" 2>&1; then
                error "Failed to extract $archive_name (corrupted archive?)"
            fi
            ;;
        *)
            error "Unsupported archive format: $ARTIFACT_FORMAT"
            ;;
    esac

    rm -f "$archive_name"
    success "Extracted archive"

    # Determine the binary location
    local binary_source
    if [ -n "$BINARY_PATH" ]; then
        binary_source="$extract_dir/$BINARY_PATH"
    else
        binary_source="$extract_dir"
    fi

    # Validate binary source exists
    if [ ! -d "$binary_source" ] && [ ! -f "$binary_source" ]; then
        error "Binary source not found: $binary_source

The extracted archive structure may be different than expected.
Contents of extracted directory:
$(ls -la "$extract_dir" 2>/dev/null || echo "  (directory not found)")

If binaries are in a subdirectory, add 'binary_path' to your config:
  binary_path: \"subdirectory/name\""
    fi

    # Build packages for each Debian distribution IN PARALLEL
    info "Building packages for all distributions in parallel..."

    declare -a dist_pids=()
    declare -a dist_names=()
    local dist_count=0

    for dist in $DISTRIBUTIONS; do
        # Check if this architecture is supported for this distribution
        if ! is_arch_supported_for_dist "$build_arch" "$dist"; then
            info "Skipping $dist for $build_arch (not supported in this distribution)"
            continue
        fi

        dist_count=$((dist_count + 1))
        info "Starting build for $dist..."

        # Build distribution in background
        (
            if build_distribution "$build_arch" "$dist" "$binary_source"; then
                echo "SUCCESS" > "build_${build_arch}_${dist}.status"
            else
                echo "FAILED" > "build_${build_arch}_${dist}.status"
                exit 1
            fi
        ) > "build_${build_arch}_${dist}.log" 2>&1 &

        dist_pids+=($!)
        dist_names+=("$dist")
    done

    if [ $dist_count -eq 0 ]; then
        warning "No packages built for $build_arch (all distributions skipped)"
        rm -rf "$extract_dir" || true
        return 0
    fi

    # Wait for all distribution builds to complete
    info "Waiting for $dist_count distribution builds to complete..."
    local failed_dists=()

    for i in "${!dist_pids[@]}"; do
        pid=${dist_pids[$i]}
        dist=${dist_names[$i]}

        if wait $pid; then
            success "Built ${PACKAGE_NAME} for $dist"
        else
            failed_dists+=("$dist")
            warning "Failed to build for $dist"
        fi

        # Clean up status files
        rm -f "build_${build_arch}_${dist}.status"
    done

    # Display any failures
    if [ ${#failed_dists[@]} -gt 0 ]; then
        error "Failed to build $build_arch for distributions: ${failed_dists[*]}

Check logs:
$(for dist in "${failed_dists[@]}"; do
    echo "  build_${build_arch}_${dist}.log"
done)"
    fi

    # Clean up log files
    for dist in "${dist_names[@]}"; do
        rm -f "build_${build_arch}_${dist}.log"
    done

    # Clean up extracted directory
    rm -rf "$extract_dir" || true

    success "Successfully built for $build_arch ($dist_count packages)"
    return 0
}

# Function to build architecture with logging to file (for parallel builds)
build_architecture_parallel() {
    local build_arch=$1
    local log_file="build_${build_arch}.log"

    # Redirect all output to log file
    {
        if build_architecture "$build_arch"; then
            echo "SUCCESS" > "build_${build_arch}.status"
        else
            echo "FAILED" > "build_${build_arch}.status"
            return 1
        fi
    } > "$log_file" 2>&1
}

# Function to build all architectures sequentially
build_architecture_sequential() {
    local arch_array=("$@")
    local total_archs=${#arch_array[@]}
    local current=0

    echo "Building architectures sequentially..."
    echo ""

    for build_arch in "${arch_array[@]}"; do
        ((current++))
        echo "=========================================="
        echo "Building $current/$total_archs: $build_arch"
        echo "=========================================="

        if ! build_architecture "$build_arch"; then
            echo "❌ Failed to build for $build_arch"
            exit 1
        fi
        echo ""
    done
}

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

# Function to monitor parallel builds
monitor_builds() {
    local pids=("$@")
    local completed=0
    local total=${#pids[@]}
    local failed_archs=()

    while [ $completed -lt $total ]; do
        completed=0
        for pid in "${pids[@]}"; do
            if ! kill -0 $pid 2>/dev/null; then
                ((completed++))
            fi
        done

        # Show progress
        echo -ne "\r⏳ Progress: $completed/$total architectures completed"
        sleep 1
    done
    echo ""

    # Check for failures
    for arch_file in build_*.status; do
        if [ -f "$arch_file" ]; then
            arch=$(echo "$arch_file" | sed 's/build_\(.*\)\.status/\1/')
            status=$(cat "$arch_file")
            if [ "$status" = "FAILED" ]; then
                failed_archs+=("$arch")
            fi
            rm -f "$arch_file"
        fi
    done

    # Display results
    if [ ${#failed_archs[@]} -gt 0 ]; then
        echo ""
        echo "❌ Failed architectures: ${failed_archs[*]}"
        echo ""
        echo "=== Build Logs ==="
        for arch in "${failed_archs[@]}"; do
            echo ""
            echo "--- $arch ---"
            cat "build_${arch}.log" 2>/dev/null || echo "No log available"
        done
        return 1
    fi

    return 0
}

# Main build logic
if [ "$ARCH" = "all" ]; then
    echo "🚀 Building $PACKAGE_NAME $VERSION-$BUILD_VERSION for all supported architectures..."

    # Get all supported architectures from config
    ARCHITECTURES=$(get_supported_architectures)
    ARCH_ARRAY=($ARCHITECTURES)
    TOTAL_ARCHS=${#ARCH_ARRAY[@]}

    if [ "$PARALLEL_BUILDS" = "true" ]; then
        echo "⚡ Parallel builds enabled (max: $MAX_PARALLEL concurrent)"
        echo ""

        declare -a pids=()
        declare -a active_archs=()
        local arch_index=0

        # Start initial batch of builds
        for build_arch in "${ARCH_ARRAY[@]}"; do
            if [ ${#pids[@]} -lt $MAX_PARALLEL ]; then
                echo "🔨 Starting build for $build_arch (${arch_index}/$TOTAL_ARCHS)..."
                build_architecture_parallel "$build_arch" &
                pids+=($!)
                active_archs+=("$build_arch")
                ((arch_index++))
            else
                break
            fi
        done

        # As builds complete, start new ones
        while [ $arch_index -lt $TOTAL_ARCHS ] || [ ${#pids[@]} -gt 0 ]; do
            # Check for completed builds
            for i in "${!pids[@]}"; do
                pid=${pids[$i]}
                if ! kill -0 $pid 2>/dev/null; then
                    # Build completed
                    wait $pid
                    exit_code=$?

                    arch=${active_archs[$i]}
                    if [ $exit_code -eq 0 ]; then
                        echo "✅ Completed build for $arch"
                    else
                        echo "❌ Failed build for $arch"
                    fi

                    # Remove from active arrays
                    unset pids[$i]
                    unset active_archs[$i]
                    pids=("${pids[@]}")  # Reindex
                    active_archs=("${active_archs[@]}")

                    # Start next build if available
                    if [ $arch_index -lt $TOTAL_ARCHS ]; then
                        next_arch="${ARCH_ARRAY[$arch_index]}"
                        echo "🔨 Starting build for $next_arch ($((arch_index+1))/$TOTAL_ARCHS)..."
                        build_architecture_parallel "$next_arch" &
                        pids+=($!)
                        active_archs+=("$next_arch")
                        ((arch_index++))
                    fi

                    break
                fi
            done

            sleep 1
        done

        # Check for any failures
        failed=false
        for arch in "${ARCH_ARRAY[@]}"; do
            if [ -f "build_${arch}.status" ]; then
                status=$(cat "build_${arch}.status")
                if [ "$status" = "FAILED" ]; then
                    failed=true
                    echo ""
                    echo "❌ Build failed for $arch. Log:"
                    cat "build_${arch}.log"
                fi
                rm -f "build_${arch}.status" "build_${arch}.log"
            fi
        done

        if [ "$failed" = "true" ]; then
            echo ""
            echo "❌ Some builds failed"
            exit 1
        fi

    else
        # Sequential builds (original behavior)
        build_architecture_sequential "${ARCH_ARRAY[@]}"
    fi

    echo ""
    echo "=========================================="
    echo "🎉 All architectures built successfully!"
    echo "=========================================="
    echo ""
    echo "Generated packages:"
    ls -lh ${PACKAGE_NAME}_*.deb | awk '{print "  " $9 " (" $5 ")"}'
    echo ""
    TOTAL_PACKAGES=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | wc -l)
    echo "✅ Total: $TOTAL_PACKAGES packages"

    # Generate build summary JSON
    generate_build_summary
else
    # Build for single architecture
    echo "Building for single architecture: $ARCH"
    echo ""

    if ! build_architecture "$ARCH"; then
        exit 1
    fi

    echo ""
    echo "Generated packages:"
    ls -lh ${PACKAGE_NAME}_*.deb | awk '{print "  " $9 " (" $5 ")"}'
    echo ""
    TOTAL_PACKAGES=$(ls ${PACKAGE_NAME}_*.deb 2>/dev/null | wc -l)
    echo "✅ Total: $TOTAL_PACKAGES packages"

    # Generate build summary JSON
    generate_build_summary
fi
