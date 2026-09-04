#!/bin/bash

# Core build functions

# Function to build a package for a specific distribution
build_distribution() {
    local build_arch=$1
    local dist=$2
    local binary_source=$3

    # Debian policy requires the Version field to start with a digit, but
    # upstream release tags commonly have a non-digit prefix - not just a
    # leading "v" (e.g. v0.64.0), but sometimes a project-name prefix too
    # (e.g. bun's tags are "bun-v1.3.14"). Strip any leading run of
    # non-digit characters rather than just a single "v"/"V". The raw
    # $VERSION (with the original prefix) is still used for the GitHub
    # release lookup/download elsewhere - only the Debian-facing version
    # drops it.
    local debian_version
    debian_version=$(echo "$VERSION" | sed -E 's/^[^0-9]*//')
    FULL_VERSION="${debian_version}-${BUILD_VERSION}+${dist}_${build_arch}"

    # Docker build with failure capture
    local docker_build_log="/tmp/docker-build-${dist}-${build_arch}.log"

    docker build \
        --progress=plain \
        --tag "${PACKAGE_NAME}-${dist}-${build_arch}" \
        --file "$SCRIPT_DIR/Dockerfile" \
        --build-arg DEBIAN_DIST="$dist" \
        --build-arg PACKAGE_NAME="$PACKAGE_NAME" \
        --build-arg VERSION="$debian_version" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$FULL_VERSION" \
        --build-arg ARCH="$build_arch" \
        --build-arg BINARY_SOURCE="$binary_source" \
        --build-arg BINARY_RENAME="$BINARY_RENAME" \
        --build-arg BUNDLE="$BUNDLE" \
        --build-arg DEPENDS="$DEPENDS" \
        --build-arg GITHUB_REPO="$GITHUB_REPO" \
        --build-arg DESCRIPTION="$PACKAGE_DESCRIPTION" \
        --build-arg MAINTAINER="$PACKAGE_MAINTAINER" \
        --build-arg LICENSE_SPDX="$LICENSE_SPDX" \
        --build-arg LICENSE_TEXT="$LICENSE_TEXT" \
        . 2>&1 | tee "$docker_build_log"
    local docker_exit=${PIPESTATUS[0]}
    if [ $docker_exit -ne 0 ]; then

        # Capture Docker build failure details for telemetry
        local docker_error=$(tail -20 "$docker_build_log" | grep -E "(ERROR|error|Error|failed|Failed|FAILED)" | head -5 | tr '\n' '; ' | sed 's/; $//')
        if [ -z "$docker_error" ]; then
            docker_error="Docker build failed for ${dist}-${build_arch} - check build logs"
        fi

        # Record detailed failure in telemetry
        record_build_failure "docker_build" "$docker_error" "1" "$build_arch" "$dist"

        # Add context-specific failure details
        add_failure_detail "Docker build failed for architecture: ${build_arch}, distribution: ${dist}"
        add_failure_detail "Docker image target: ${PACKAGE_NAME}-${dist}-${build_arch}"

        # Extract specific error patterns for better categorization
        if echo "$docker_error" | grep -qi -E "(no such file|not found|file.*missing)"; then
            add_failure_detail "Missing files or dependencies detected in Docker build"
            record_build_failure "docker_build" "Missing files or dependencies in Docker build: $docker_error" "1" "$build_arch" "$dist"
        elif echo "$docker_error" | grep -qi -E "(permission|denied|access)"; then
            add_failure_detail "Permission error during Docker build"
            record_build_failure "docker_build" "Permission error in Docker build: $docker_error" "1" "$build_arch" "$dist"
        elif echo "$docker_error" | grep -qi -E "(memory|disk|space|resource)"; then
            add_failure_detail "Resource constraint during Docker build"
            record_build_failure "docker_build" "Resource constraint in Docker build: $docker_error" "1" "$build_arch" "$dist"
        elif echo "$docker_error" | grep -qi -E "(network|connection|timeout|download)"; then
            add_failure_detail "Network issue during Docker build"
            record_build_failure "docker_build" "Network issue in Docker build: $docker_error" "1" "$build_arch" "$dist"
        else
            add_failure_detail "General Docker build failure"
            record_build_failure "docker_build" "Docker build error: $docker_error" "1" "$build_arch" "$dist"
        fi

        # Add build environment details
        add_failure_detail "Build environment: $(uname -a)"
        add_failure_detail "Docker version: $(docker --version 2>/dev/null || echo 'Docker not available')"

        # Clean up log file
        rm -f "$docker_build_log" 2>/dev/null || true

        return 1
    fi

    # Clean up successful build log
    rm -f "$docker_build_log" 2>/dev/null || true

    # Extract package using docker create/cp (works with single-stage and scratch images)
    local container_id
    container_id="$(docker create "${PACKAGE_NAME}-${dist}-${build_arch}" / 2>/dev/null || echo "")"
    if [ -n "$container_id" ]; then
        if docker cp "$container_id:/${PACKAGE_NAME}_${FULL_VERSION}.deb" "./${PACKAGE_NAME}_${FULL_VERSION}.deb" 2>/dev/null; then
            docker rm "$container_id" >/dev/null 2>&1 || true
        else
            docker rm "$container_id" >/dev/null 2>&1 || true
            # Remove any empty/partial leftover so it cannot be counted or uploaded
            rm -f "./${PACKAGE_NAME}_${FULL_VERSION}.deb"
            return 1
        fi
    else
        return 1
    fi

    # Clean up Docker image to save space
    docker rmi "${PACKAGE_NAME}-${dist}-${build_arch}" 2>/dev/null || true

    # Verify the .deb package was created and is non-empty
    if [ ! -s "./${PACKAGE_NAME}_${FULL_VERSION}.deb" ]; then
        # Remove the empty file so it cannot be counted or uploaded as a package
        rm -f "./${PACKAGE_NAME}_${FULL_VERSION}.deb"
        record_build_failure "package_extraction" "Generated .deb package is missing or empty: ./${PACKAGE_NAME}_${FULL_VERSION}.deb" "1" "$build_arch" "$dist"
        add_failure_detail "Package file not found or empty after build: ./${PACKAGE_NAME}_${FULL_VERSION}.deb"
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
        echo "⚠️  Architecture '$build_arch' skipped: no release assets available for this version"
        echo "   💡 This architecture is not available for $PACKAGE_NAME version $VERSION"
        echo ""
        # Record that this architecture was skipped (not failed)
        echo "$build_arch" >> "/tmp/skipped_architectures.txt"
        return 0  # Return success so build continues with other architectures
    fi
    echo "$build_arch" >> "/tmp/attempted_architectures.txt"

    echo "==========================================="
    info "Building for architecture: $build_arch"
    info "Release pattern: $release_pattern"
    echo "==========================================="

    # Extract filename without extension for directory name
    local archive_name="${release_pattern}"
    local extract_dir="${archive_name%.tar.gz}"
    extract_dir="${extract_dir%.zip}"
    extract_dir="${extract_dir%.tgz}"
    extract_dir="${extract_dir%.tar.xz}"
    extract_dir="${extract_dir%.tar.bz2}"
    extract_dir="${extract_dir%.tar.zst}"
    extract_dir="${extract_dir%.gz}"

    # Clean up any previous builds for this architecture
    if [ -d "$extract_dir" ] || [ -f "$archive_name" ]; then
        info "Cleaning up previous build artifacts..."
        rm -rf "$extract_dir" || true
        rm -f "$archive_name" || true
    fi

    # Download the release artifact with caching
    info "Preparing to download: $release_pattern"
    
    # Get expected checksum if available. Prefer the vet-time provenance pin
    # over the release's live checksum file: the pin was recorded under
    # human review at vet time, so an upstream release that was altered
    # afterwards (asset AND its own checksum file replaced together) is
    # still caught. A matching pin is enforced strictly - download_with_cache
    # hard-fails on mismatch.
    local expected_checksum=""
    if command -v fetch_pinned_checksum >/dev/null 2>&1; then
        local pinned
        pinned=$(fetch_pinned_checksum "$VERSION" "$release_pattern" 2>/dev/null || echo "")
        if [ -n "$pinned" ]; then
            expected_checksum="$pinned"
            info "Provenance: $release_pattern verified against vetted pin (sha256:$pinned, recorded at vet time)"
        else
            info "Provenance: no vetted pin for $release_pattern @ $VERSION; falling back to live checksum verification"
        fi
    fi
    if [ -z "$expected_checksum" ] && command -v fetch_checksum_for_asset >/dev/null 2>&1; then
        expected_checksum=$(fetch_checksum_for_asset "$release_pattern" 2>/dev/null || echo "")
    fi
    
    # Validate release exists before downloading
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${release_pattern}"
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
    
    # Source download cache library if not already loaded via lazy-loading
    if ! command -v download_with_cache >/dev/null 2>&1; then
        source "$SCRIPT_DIR/lib/download-cache.sh"
    fi
    
    # Download with caching
    if ! download_release_asset "$release_pattern" "$archive_name" "$expected_checksum"; then
        error "Failed to download release for $build_arch"
    fi

    # Verify checksum if available
    verify_checksum "$archive_name" "$release_pattern"

    # Extract the archive based on format (ONCE for all distributions)
    info "Extracting $archive_name..."
    case "$ARTIFACT_FORMAT" in
        "tar.gz"|"tgz"|"tar.xz"|"tar.bz2"|"tar.zst")
            # Detect if archive has a top-level subdirectory matching extract_dir.
            # Flat archives (e.g. single binary) are extracted into extract_dir.
            #
            # A name match alone isn't enough: some upstreams (e.g.
            # mikefarah/yq) ship a flat archive whose binary happens to be
            # named identically to the archive's own basename (both
            # "yq_linux_loong64"), which isn't a wrapping directory at all -
            # extracting "in place" for that case leaves no directory at
            # extract_dir, only a same-named file, and the later COPY into
            # the build container fails. Requiring the raw tar entry to
            # actually be a directory member (name followed by "/")
            # distinguishes the two cases.
            #
            # No -z/-J: GNU tar auto-detects gzip/xz/bzip2/zstd compression
            # from the archive itself, so one path covers every tar variant
            # above instead of a per-compression branch.
            local top_raw top_entry top_is_dir=false
            top_raw=$(tar -tf "$archive_name" 2>/dev/null | head -1 | sed 's|^\./||')
            top_entry=$(echo "$top_raw" | sed 's|/.*||')
            case "$top_raw" in
                "$top_entry"/*) top_is_dir=true ;;
            esac
            if [ "$top_entry" = "$extract_dir" ] && [ "$top_is_dir" = true ]; then
                if ! tar -xf "$archive_name" 2>&1; then
                    error "Failed to extract $archive_name (corrupted archive?)"
                fi
            else
                mkdir -p "$extract_dir"
                if ! tar -xf "$archive_name" -C "$extract_dir" 2>&1; then
                    error "Failed to extract $archive_name (corrupted archive?)"
                fi
            fi
            ;;
        "zip")
            # Same directory-vs-same-named-file distinction as the tar.gz
            # case above.
            local zip_top_raw zip_top zip_top_is_dir=false
            zip_top_raw=$(unzip -Z1 "$archive_name" 2>/dev/null | head -1)
            zip_top=$(echo "$zip_top_raw" | sed 's|/.*||')
            case "$zip_top_raw" in
                "$zip_top"/*) zip_top_is_dir=true ;;
            esac
            if [ "$zip_top" = "$extract_dir" ] && [ "$zip_top_is_dir" = true ]; then
                if ! unzip -q "$archive_name" 2>&1; then
                    error "Failed to extract $archive_name (corrupted archive?)"
                fi
            else
                mkdir -p "$extract_dir"
                if ! unzip -q "$archive_name" -d "$extract_dir" 2>&1; then
                    error "Failed to extract $archive_name (corrupted archive?)"
                fi
            fi
            ;;
        "raw")
            # No archive - the downloaded file IS the binary (e.g.
            # jandedobbeleer/oh-my-posh's "posh-linux-amd64", no .tar.*/.zip
            # wrapper). extract_dir was derived by stripping known archive
            # suffixes from archive_name, which is a no-op here since there's
            # no suffix to strip - it would otherwise equal archive_name
            # itself and collide with the file mkdir is about to create a
            # directory over. Move the file into a distinctly-named
            # directory instead so it looks like any other flat single-file
            # archive to the packaging step that follows (which already
            # handles that shape for real archives).
            extract_dir="${extract_dir}.d"
            mkdir -p "$extract_dir"
            mv "$archive_name" "$extract_dir/"
            ;;
        "gz")
            # Gzipped single binary (e.g. TomWright/dasel's
            # "dasel_linux_amd64.gz"). Decompress in place, then treat
            # like raw - move the decompressed binary into extract_dir.
            extract_dir="${extract_dir}.d"
            mkdir -p "$extract_dir"
            gunzip -c "$archive_name" > "$extract_dir/$(basename "$archive_name" .gz)"
            rm -f "$archive_name"
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

    # Validate binary source exists. binary_path may contain a glob (e.g.
    # "dist/*") for upstreams whose wrapping directory name embeds the
    # version/arch and so can't be hardcoded (e.g. superfile's release
    # archives nest the binary at dist/superfile-linux-v<VERSION>-<ARCH>/).
    # Testing the literal string would always report "not found" since no
    # path literally contains an asterisk - expand it here instead, and
    # resolve binary_source to the actual matched path so every downstream
    # use (including the Docker build-arg) gets a concrete path rather than
    # depending on Docker COPY's own glob semantics a second time.
    if [ ! -e "$binary_source" ]; then
        local glob_match=""
        for candidate in $binary_source; do
            if [ -e "$candidate" ]; then
                glob_match="$candidate"
                break
            fi
        done
        if [ -n "$glob_match" ]; then
            binary_source="$glob_match"
        fi
    fi

    if [ ! -d "$binary_source" ] && [ ! -f "$binary_source" ]; then
        error "Binary source not found: $binary_source

The extracted archive structure may be different than expected.
Contents of extracted directory:
$(ls -la "$extract_dir" 2>/dev/null || echo "  (directory not found)")

If binaries are in a subdirectory, add 'binary_path' to your config:
  binary_path: \"subdirectory/name\""
    fi

    # Build each distribution for this architecture. Dist builds are run
    # SEQUENTIALLY per architecture: architecture workers are already
    # parallelized by the resource pool (up to MAX_PARALLEL), and
    # backgrounding the distributions on top of that multiplied concurrent
    # docker builds by the dist count (e.g. 3 workers x 4 dists = 12
    # simultaneous builds), which exhausted shared CI runners and produced
    # scattered failures. Serializing keeps peak docker concurrency at the
    # resource-pool budget.
    declare -a dist_names=()
    local dist_count=0
    local failed_dists=()

    for dist in $DISTRIBUTIONS; do
        # Skip bare '-' or 'null' tokens from yq formatting artifacts
        [ "$dist" = "-" ] || [ "$dist" = "null" ] && continue
        # Check if this architecture is supported for this distribution
        if ! is_arch_supported_for_dist "$build_arch" "$dist"; then
            info "Skipping $dist for $build_arch (not supported in this distribution)"
            continue
        fi

        dist_count=$((dist_count + 1))
        dist_names+=("$dist")
        info "Building $dist for $build_arch..."

        if build_distribution "$build_arch" "$dist" "$binary_source" > "build_${build_arch}_${dist}.log" 2>&1; then
            success "Built ${PACKAGE_NAME} for $dist"
        else
            failed_dists+=("$dist")
            echo "   ⚠️  $dist build failed - $build_arch will try other distributions"
        fi
        rm -f "build_${build_arch}_${dist}.status"
    done

    if [ $dist_count -eq 0 ]; then
        warning "No packages built for $build_arch (all distributions skipped)"
        rm -rf "$extract_dir" || true
        return 0
    fi

    # Display any failures with clearer context
    if [ ${#failed_dists[@]} -gt 0 ]; then
        successful_dists=$((${#dist_names[@]} - ${#failed_dists[@]}))
        echo ""
        echo "   📊 Distribution Summary for $build_arch:"
        echo "      ✅ Successful: $successful_dists distributions"
        echo "      ❌ Failed: ${#failed_dists[@]} distributions (${failed_dists[*]})"
        echo "      📈 Success Rate: $(( (successful_dists * 100) / ${#dist_names[@]} ))%"
        echo ""
        echo "   📋 Failed distribution build logs:"
        for dist in "${failed_dists[@]}"; do
            echo "   --- build_${build_arch}_${dist}.log ---"
            cat "build_${build_arch}_${dist}.log" 2>/dev/null || echo "   (log not found)"
            echo "   ---"
        done
        echo ""
    fi

    # Clean up log files
    for dist in "${dist_names[@]}"; do
        rm -f "build_${build_arch}_${dist}.log"
    done

    # Clean up extracted directory
    rm -rf "$extract_dir" || true

    # Propagate failure when every distribution build failed — otherwise the
    # architecture is reported as successful even though it produced nothing
    if [ ${#dist_names[@]} -gt 0 ] && [ ${#failed_dists[@]} -eq ${#dist_names[@]} ]; then
        error_no_exit "All ${#dist_names[@]} distribution build(s) failed for $build_arch"
        return 1
    fi

    success "Successfully built for $build_arch ($dist_count packages)"
    return 0
}
