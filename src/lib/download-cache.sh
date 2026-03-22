#!/bin/bash

# Download caching and management functions

# Global download cache directory
DOWNLOAD_CACHE_DIR="/tmp/download_cache"
mkdir -p "$DOWNLOAD_CACHE_DIR"

# Function to generate content-based cache key
get_cache_key() {
    local url="$1"
    local checksum="$2"
    
    # Create cache key based on URL and checksum if available
    if [ -n "$checksum" ]; then
        echo "$(echo -n "${url}:${checksum}" | sha256sum | cut -d' ' -f1)"
    else
        echo "$(echo -n "$url" | sha256sum | cut -d' ' -f1)"
    fi
}

# Function to download with caching
download_with_cache() {
    local url="$1"
    local output_file="$2"
    local expected_checksum="$3"
    local cache_key
    
    cache_key=$(get_cache_key "$url" "$expected_checksum")
    local cache_file="${DOWNLOAD_CACHE_DIR}/${cache_key}"
    local cache_meta="${cache_file}.meta"
    
    # Check if file exists in cache and is valid
    if [ -f "$cache_file" ] && [ -f "$cache_meta" ]; then
        local cached_url=$(cat "$cache_meta" 2>/dev/null || echo "")
        local cached_time=$(stat -c %Y "$cache_file" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local cache_age=$((current_time - cached_time))
        
        # Cache is valid for 24 hours (86400 seconds)
        if [ $cache_age -lt 86400 ] && [ "$cached_url" = "$url" ]; then
            # Verify cached file if checksum is provided
            if [ -n "$expected_checksum" ]; then
                local actual_checksum=$(sha256sum "$cache_file" | cut -d' ' -f1)
                if [ "$actual_checksum" = "$expected_checksum" ]; then
                    info "Using cached download for $(basename "$output_file")"
                    cp "$cache_file" "$output_file"
                    return 0
                else
                    warning "Cached file checksum mismatch, re-downloading"
                    rm -f "$cache_file" "$cache_meta"
                fi
            else
                info "Using cached download for $(basename "$output_file")"
                cp "$cache_file" "$output_file"
                return 0
            fi
        else
            # Remove stale cache
            rm -f "$cache_file" "$cache_meta" 2>/dev/null || true
        fi
    fi
    
    # Use file locking to prevent race conditions in parallel downloads
    local lock_file="${cache_file}.lock"
    (
        flock -x 200
        
        # Double-check cache after acquiring lock
        if [ -f "$cache_file" ] && [ -f "$cache_meta" ]; then
            local cached_url=$(cat "$cache_meta" 2>/dev/null || echo "")
            local cached_time=$(stat -c %Y "$cache_file" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local cache_age=$((current_time - cached_time))
            
            if [ $cache_age -lt 86400 ] && [ "$cached_url" = "$url" ]; then
                if [ -n "$expected_checksum" ]; then
                    local actual_checksum=$(sha256sum "$cache_file" | cut -d' ' -f1)
                    if [ "$actual_checksum" = "$expected_checksum" ]; then
                        info "Using cached download for $(basename "$output_file")"
                        cp "$cache_file" "$output_file"
                        exit 0
                    fi
                else
                    info "Using cached download for $(basename "$output_file")"
                    cp "$cache_file" "$output_file"
                    exit 0
                fi
            fi
        fi
        
        # Download with progress and retry logic
        info "Downloading $(basename "$output_file")..."
        
        local max_retries=3
        local retry_delay=1
        local attempt=0
        
        while [ $attempt -lt $max_retries ]; do
            if curl -fL --progress-bar --connect-timeout 30 --max-time 300 \
                   -o "${cache_file}.tmp" "$url" 2>&1; then
                # Download successful
                
                # Verify checksum if provided
                if [ -n "$expected_checksum" ]; then
                    local actual_checksum=$(sha256sum "${cache_file}.tmp" | cut -d' ' -f1)
                    if [ "$actual_checksum" != "$expected_checksum" ]; then
                        rm -f "${cache_file}.tmp"
                        error "Checksum verification failed for $(basename "$output_file")
Expected: $expected_checksum
Actual:   $actual_checksum"
                        exit 1
                    fi
                fi
                
                # Move to final cache location
                mv "${cache_file}.tmp" "$cache_file"
                echo "$url" > "$cache_meta"
                
                # Copy to output location
                cp "$cache_file" "$output_file"
                success "Downloaded and cached $(basename "$output_file")"
                exit 0
            else
                attempt=$((attempt + 1))
                if [ $attempt -lt $max_retries ]; then
                    warning "Download failed, retrying in ${retry_delay}s... (attempt $attempt/$max_retries)"
                    sleep $retry_delay
                    retry_delay=$((retry_delay * 2))
                fi
            fi
        done
        
        # All retries failed
        rm -f "${cache_file}.tmp" "$cache_file" "$cache_meta" 2>/dev/null || true
        error "Failed to download $(basename "$output_file") after $max_retries attempts"
        exit 1
        
    ) 200>"$lock_file"
    
    local exit_code=$?
    rm -f "$lock_file" 2>/dev/null || true
    
    return $exit_code
}

# Function to download release assets with caching
download_release_asset() {
    local release_pattern="$1"
    local output_file="$2"
    local expected_checksum="$3"
    
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${release_pattern}"
    
    download_with_cache "$download_url" "$output_file" "$expected_checksum"
}

# Function to cleanup stale download cache
cleanup_download_cache() {
    if [ -d "$DOWNLOAD_CACHE_DIR" ]; then
        # Remove cache files older than 7 days
        find "$DOWNLOAD_CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null || true
        # Remove corrupted cache files
        find "$DOWNLOAD_CACHE_DIR" -name "*.tmp" -type f -mmin +60 -delete 2>/dev/null || true
        find "$DOWNLOAD_CACHE_DIR" -name "*.lock" -type f -mmin +5 -delete 2>/dev/null || true
        
        # Remove empty directory
        rmdir "$DOWNLOAD_CACHE_DIR" 2>/dev/null || true
    fi
}

# Function to get cache statistics
get_download_cache_stats() {
    if [ -d "$DOWNLOAD_CACHE_DIR" ]; then
        local cache_size=$(du -sh "$DOWNLOAD_CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
        local cache_files=$(find "$DOWNLOAD_CACHE_DIR" -name "*.cache" -type f | wc -l)
        echo "Cache: $cache_files files, $cache_size"
    else
        echo "Cache: empty"
    fi
}