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
