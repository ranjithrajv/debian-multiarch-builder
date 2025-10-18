#!/bin/bash

# Core build functions

# Function to build a package for a specific distribution
build_distribution() {
    local build_arch=$1
    local dist=$2
    local binary_source=$3

    FULL_VERSION="${VERSION}-${BUILD_VERSION}+${dist}_${build_arch}"

    if ! docker build . -t "${PACKAGE_NAME}-${dist}-${build_arch}" \
        -f "$SCRIPT_DIR/Dockerfile" \
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

    # Run lintian check on the built package
    if ! run_lintian_check "./${PACKAGE_NAME}_${FULL_VERSION}.deb"; then
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
