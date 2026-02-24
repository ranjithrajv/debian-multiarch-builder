#!/bin/bash

# GitHub API interaction functions

# Global cache directory for API responses
API_CACHE_DIR="/tmp/github_api_cache"
mkdir -p "$API_CACHE_DIR"

# Function to implement exponential backoff for API calls
api_call_with_retry() {
    local url="$1"
    local max_retries=3
    local retry_delay=1
    local attempt=0
    
    while [ $attempt -lt $max_retries ]; do
        local response=$(curl -sL \
            -H "Accept: application/vnd.github.v3+json" \
            -w "\n%{http_code}\n%{http_code}\n" \
            "$url" 2>/dev/null)
        
        local http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | head -n -2)
        
        # Check for rate limiting
        if [ "$http_code" = "429" ] || [ "$http_code" = "403" ]; then
            local rate_limit_remaining=$(curl -s -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/rate_limit" | jq -r '.rate.remaining // 0' 2>/dev/null)
            
            if [ "$rate_limit_remaining" = "0" ]; then
                local reset_time=$(curl -s -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/rate_limit" | jq -r '.rate.reset // 0' 2>/dev/null)
                local current_time=$(date +%s)
                local sleep_time=$((reset_time - current_time + 1))
                
                if [ $sleep_time -gt 0 ] && [ $sleep_time -lt 300 ]; then
                    warning "GitHub API rate limit hit. Waiting ${sleep_time}s for reset..."
                    sleep $sleep_time
                    continue
                fi
            fi
        fi
        
        # Success response
        if [ "$http_code" = "200" ]; then
            echo "$body"
            return 0
        fi
        
        # Handle other errors
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_retries ]; then
            warning "API call failed (HTTP $http_code), retrying in ${retry_delay}s... (attempt $attempt/$max_retries)"
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))
        fi
    done
    
    error "API call failed after $max_retries attempts"
    return 1
}

# Function to fetch release assets from GitHub API with enhanced caching
fetch_release_assets() {
    # Generate cache file path (replace / with _ in repo name)
    local cache_file="${API_CACHE_DIR}/release_assets_${GITHUB_REPO//\//_}_${VERSION}.cache"
    local cache_meta="${cache_file}.meta"
    
    # Check if cached file exists and is fresh (less than 5 minutes old)
    if [ -f "$cache_file" ] && [ -f "$cache_meta" ]; then
        local cache_time=$(cat "$cache_meta" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local cache_age=$((current_time - cache_time))
        
        # Cache is valid for 5 minutes (300 seconds)
        if [ $cache_age -lt 300 ]; then
            cat "$cache_file"
            return 0
        else
            # Remove stale cache
            rm -f "$cache_file" "$cache_meta" 2>/dev/null || true
        fi
    fi

    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${VERSION}"
    info "Fetching release assets from GitHub API..."

    # Use file locking to prevent race conditions in parallel builds
    local lock_file="${cache_file}.lock"
    (
        flock -x 200
        
        # Double-check cache after acquiring lock (another process might have updated it)
        if [ -f "$cache_file" ] && [ -f "$cache_meta" ]; then
            local cache_time=$(cat "$cache_meta" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local cache_age=$((current_time - cache_time))
            
            if [ $cache_age -lt 300 ]; then
                cat "$cache_file"
                exit 0
            fi
        fi
        
        # Make API call with retry logic
        local assets_json=$(api_call_with_retry "$api_url")
        local assets=$(echo "$assets_json" | jq -r '.assets[]? | .name' 2>/dev/null)
        
        if [ -z "$assets" ]; then
            error "Failed to fetch release assets from $api_url

Possible reasons:
  - Version '$VERSION' doesn't exist for $GITHUB_REPO
  - GitHub API rate limit exceeded
  - Network connectivity issues

Please check: https://github.com/${GITHUB_REPO}/releases/tag/${VERSION}"
            exit 1
        fi

        # Write to cache files atomically
        echo "$assets" > "${cache_file}.tmp" && mv "${cache_file}.tmp" "$cache_file"
        echo "$(date +%s)" > "$cache_meta"
        echo "$assets"
        
    ) 200>"$lock_file"
    
    local exit_code=$?
    rm -f "$lock_file" 2>/dev/null || true
    
    if [ $exit_code -eq 0 ]; then
        cat "$cache_file"
    else
        return 1
    fi
}

# Function to fetch full release data (for validation and other uses)
fetch_release_data() {
    local cache_file="${API_CACHE_DIR}/release_data_${GITHUB_REPO//\//_}_${VERSION}.cache"
    local cache_meta="${cache_file}.meta"
    
    # Check cache freshness (5 minutes)
    if [ -f "$cache_file" ] && [ -f "$cache_meta" ]; then
        local cache_time=$(cat "$cache_meta" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local cache_age=$((current_time - cache_time))
        
        if [ $cache_age -lt 300 ]; then
            cat "$cache_file"
            return 0
        else
            rm -f "$cache_file" "$cache_meta" 2>/dev/null || true
        fi
    fi

    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${VERSION}"
    
    # Use file locking
    local lock_file="${cache_file}.lock"
    (
        flock -x 200
        
        # Double-check cache
        if [ -f "$cache_file" ] && [ -f "$cache_meta" ]; then
            local cache_time=$(cat "$cache_meta" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local cache_age=$((current_time - cache_time))
            
            if [ $cache_age -lt 300 ]; then
                cat "$cache_file"
                exit 0
            fi
        fi
        
        local release_data=$(api_call_with_retry "$api_url")
        
        if [ -z "$release_data" ]; then
            exit 1
        fi
        
        # Cache the response
        echo "$release_data" > "${cache_file}.tmp" && mv "${cache_file}.tmp" "$cache_file"
        echo "$(date +%s)" > "$cache_meta"
        echo "$release_data"
        
    ) 200>"$lock_file"
    
    local exit_code=$?
    rm -f "$lock_file" 2>/dev/null || true
    
    if [ $exit_code -eq 0 ]; then
        cat "$cache_file"
    else
        return 1
    fi
}

# Function to cleanup API cache files
cleanup_api_cache() {
    # Clean up current version cache files
    local cache_pattern="${API_CACHE_DIR}/release_assets_${GITHUB_REPO//\//_}_${VERSION}.cache*"
    rm -f $cache_pattern 2>/dev/null || true
    
    local data_pattern="${API_CACHE_DIR}/release_data_${GITHUB_REPO//\//_}_${VERSION}.cache*"
    rm -f $data_pattern 2>/dev/null || true
}

# Function to cleanup all stale API cache files (older than 1 hour)
cleanup_all_api_cache() {
    if [ -d "$API_CACHE_DIR" ]; then
        # Remove cache files older than 1 hour
        find "$API_CACHE_DIR" -name "*.cache" -type f -mmin +60 -delete 2>/dev/null || true
        find "$API_CACHE_DIR" -name "*.meta" -type f -mmin +60 -delete 2>/dev/null || true
        find "$API_CACHE_DIR" -name "*.lock" -type f -mmin +5 -delete 2>/dev/null || true
        
        # Remove empty directory
        rmdir "$API_CACHE_DIR" 2>/dev/null || true
    fi
}
