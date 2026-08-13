#!/bin/bash

# Release and checksum validation functions

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

# Read the vet-time provenance pin (release-metadata.json, path in
# PINNED_METADATA) and echo the pinned SHA-256 when it covers exactly this
# release tag + asset. Returns 0 with the hash when the pin applies;
# returns 1 when there is no pin, the file is missing, or the pin covers a
# different release/asset.
#
# This is the supply-chain anchor: the digest was recorded under human
# review at vet time, so a release that was altered after vetting - asset
# AND its own checksum file replaced together - is still caught here.
fetch_pinned_checksum() {
    local version="$1" release_pattern="$2"
    local meta="${PINNED_METADATA:-}"
    [ -n "$meta" ] && [ -f "$meta" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    local pin_version pin_asset pin_sha
    pin_version=$(jq -r '.version // empty' "$meta" 2>/dev/null || true)
    pin_asset=$(jq -r '.asset // empty' "$meta" 2>/dev/null || true)
    pin_sha=$(jq -r '.sha256 // empty' "$meta" 2>/dev/null || true)

    [ -n "$pin_version" ] && [ "$pin_version" = "$version" ] || return 1
    [ -n "$pin_asset" ] && [ "$pin_asset" = "$release_pattern" ] || return 1
    [[ "$pin_sha" =~ ^[a-f0-9]{64}$ ]] || return 1

    echo "$pin_sha"
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

    # Download checksum file with caching
    local checksum_url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${checksum_file}"
    info "Found checksum file: $checksum_file"
    
    # Source download cache library if not already loaded
    if ! command -v download_with_cache >/dev/null 2>&1; then
        source "$SCRIPT_DIR/lib/download-cache.sh"
    fi

    if ! download_with_cache "$checksum_url" "$checksum_file"; then
        warning "Failed to download checksum file, skipping verification"
        return 0
    fi

    # Extract the checksum for our specific file
    local expected_checksum=""
    if grep -q "$archive_name" "$checksum_file" 2>/dev/null; then
        local match_line=$(grep "$archive_name" "$checksum_file" | head -1)
        local first_field=$(echo "$match_line" | awk '{print $1}')
        if [ "$first_field" = "$archive_name" ]; then
            # "Filename-first" checksum layout (e.g. GoReleaser's
            # multi-algorithm "extra checksums" template, used by
            # mikefarah/yq): field 1 is the filename itself, not a hash,
            # with one column per algorithm after it - resolve which
            # column is SHA-256 via a sibling "*_hashes_order" file
            # rather than assuming field 1 is a hash.
            expected_checksum=$(resolve_multialgo_checksum "$match_line" "$checksum_file")
        else
            expected_checksum="$first_field"
        fi
    elif [ -f "$checksum_file" ] && [ $(wc -l < "$checksum_file") -eq 1 ]; then
        # Single checksum file for single archive
        expected_checksum=$(awk '{print $1}' "$checksum_file")
    fi

    # A real SHA-256 is exactly 64 hex characters - anything else means
    # we mis-parsed the checksum file's format. Skip verification rather
    # than fail the build on our own parsing error.
    if [ -n "$expected_checksum" ] && ! [[ "$expected_checksum" =~ ^[a-f0-9]{64}$ ]]; then
        warning "Parsed checksum '$expected_checksum' doesn't look like a SHA-256 hash, skipping verification"
        expected_checksum=""
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

# Resolve a SHA-256 value from a checksum-file line where field 1 is the
# archive filename (not a hash), followed by one column per hash
# algorithm in the order listed by a sibling "<checksum_file>_hashes_order"
# file (e.g. GoReleaser's multi-algorithm "extra checksums" template,
# used by mikefarah/yq). Echoes the SHA-256 value, or nothing if the
# order file isn't available or doesn't list SHA-256.
resolve_multialgo_checksum() {
    local match_line="$1" checksum_file="$2"
    local order_file="${checksum_file}_hashes_order"
    local order_url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${order_file}"

    if ! command -v download_with_cache >/dev/null 2>&1; then
        source "$SCRIPT_DIR/lib/download-cache.sh"
    fi

    download_with_cache "$order_url" "$order_file" >&2 || return 1

    local sha256_line
    sha256_line=$(grep -n -m1 -ix "SHA-256" "$order_file" 2>/dev/null | cut -d: -f1)
    rm -f "$order_file"
    [ -n "$sha256_line" ] || return 1

    echo "$match_line" | awk -v f="$((sha256_line + 1))" '{print $f}'
}

# Function to fetch checksum for a specific asset (used by download cache)
fetch_checksum_for_asset() {
    local asset_name="$1"
    local assets=$(fetch_release_assets)
    
    # Try to find checksum file in release assets
    local checksum_patterns=("${asset_name}.sha256" "${asset_name}.sha256sum" "SHA256SUMS" "checksums.txt")
    local checksum_file=""
    
    for pattern in "${checksum_patterns[@]}"; do
        if echo "$assets" | grep -qi "^${pattern}$"; then
            checksum_file="$pattern"
            break
        fi
    done
    
    if [ -z "$checksum_file" ]; then
        return 1
    fi
    
    # Download checksum file
    local checksum_url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${checksum_file}"
    
    # Source download cache library if not already loaded
    if ! command -v download_with_cache >/dev/null 2>&1; then
        source "$SCRIPT_DIR/lib/download-cache.sh"
    fi
    
    # Redirect stdout to stderr so INFO log messages don't contaminate the return value
    if ! download_with_cache "$checksum_url" "$checksum_file" >&2; then
        return 1
    fi

    # Extract checksum for our specific asset
    local expected_checksum=""

    # Try different checksum formats
    if [ -f "$checksum_file" ]; then
        # SHA256 format: "hash  filename"
        expected_checksum=$(grep -F "$asset_name" "$checksum_file" 2>/dev/null | awk '{print $1}' | head -1)

        # If not found, try other formats
        if [ -z "$expected_checksum" ]; then
            # Format: "hash *filename" (common in GNU coreutils)
            expected_checksum=$(grep -F "$asset_name" "$checksum_file" 2>/dev/null | awk '{print $1}' | head -1)
        fi

        if [ -z "$expected_checksum" ]; then
            # Format: "hash:filename" or "hash filename" (case insensitive)
            expected_checksum=$(grep -iF "$asset_name" "$checksum_file" 2>/dev/null | awk -F'[:[:space:]]' '{print $1}' | head -1)
        fi

        # "Filename-first" layout (e.g. GoReleaser's multi-algorithm
        # "extra checksums" template, used by mikefarah/yq): the above
        # patterns all grab field 1, which is the filename itself here,
        # not a hash. Resolve the real SHA-256 column instead.
        if [ "$expected_checksum" = "$asset_name" ]; then
            local match_line=$(grep -F "$asset_name" "$checksum_file" 2>/dev/null | head -1)
            expected_checksum=$(resolve_multialgo_checksum "$match_line" "$checksum_file")
        fi

        # A real SHA-256 is exactly 64 hex characters - anything else
        # means we mis-parsed the file's format. Don't return garbage.
        if [ -n "$expected_checksum" ] && ! [[ "$expected_checksum" =~ ^[a-f0-9]{64}$ ]]; then
            expected_checksum=""
        fi

        rm -f "$checksum_file"
    fi

    if [ -n "$expected_checksum" ]; then
        echo "$expected_checksum"
        return 0
    else
        return 1
    fi
}
