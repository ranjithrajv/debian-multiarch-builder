#!/bin/bash

# Logging and output formatting functions

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Enhanced error reporting with actionable guidance
error() {
    local message="$1"
    local error_type="${2:-generic}"
    
    # Set flag to prevent double error handling in main.sh
    export SPECIFIC_ERROR_SHOWN=true
    
    echo -e "${RED}❌ ERROR: $message${NC}" >&2
    
    # Provide contextual help based on error type
    case "$error_type" in
        "config_not_found")
            echo "" >&2
            echo -e "${YELLOW}💡 Solutions:${NC}" >&2
            echo "   1. Check the file path is correct" >&2
            echo "   2. Create a configuration file (see docs/configuration-reference.md)" >&2
            echo "   3. Use a template: cp templates/rust/eza.yaml ./build-config.yaml" >&2
            echo "" >&2
            ;;
        "invalid_yaml")
            echo "" >&2
            echo -e "${YELLOW}💡 Solutions:${NC}" >&2
            echo "   1. Validate YAML syntax: yq eval '.' $1" >&2
            echo "   2. Check for indentation errors" >&2
            echo "   3. Ensure no tabs (use spaces only)" >&2
            echo "" >&2
            ;;
        "version_not_found")
            echo "" >&2
            echo -e "${YELLOW}💡 Solutions:${NC}" >&2
            echo "   1. Check version number (try without 'v' prefix)" >&2
            echo "   2. Verify repository exists" >&2
            echo "   3. Check available releases on GitHub" >&2
            echo "" >&2
            ;;
        "release_not_found")
            echo "" >&2
            echo -e "${YELLOW}💡 Solutions:${NC}" >&2
            echo "   1. Verify the version exists: curl -s https://api.github.com/repos/\$repo/releases" >&2
            echo "   2. Check download_pattern in config matches release assets" >&2
            echo "   3. Run with --dry-run to diagnose" >&2
            echo "" >&2
            ;;
        "architecture_not_available")
            echo "" >&2
            echo -e "${YELLOW}💡 Solutions:${NC}" >&2
            echo "   1. Remove this architecture from your config" >&2
            echo "   2. Check if upstream publishes this arch" >&2
            echo "   3. Use auto-discovery mode" >&2
            echo "" >&2
            ;;
        "download_failed")
            echo "" >&2
            echo -e "${YELLOW}💡 Solutions:${NC}" >&2
            echo "   1. Check network connectivity" >&2
            echo "   2. Verify release asset exists" >&2
            echo "   3. Check GitHub API rate limits" >&2
            echo "" >&2
            ;;
        "build_failed")
            echo "" >&2
            echo -e "${YELLOW}💡 Solutions:${NC}" >&2
            echo "   1. Check build log for details" >&2
            echo "   2. Verify all dependencies are installed" >&2
            echo "   3. Run with DEBUG=true for verbose output" >&2
            echo "" >&2
            ;;
        "checksum_mismatch")
            echo "" >&2
            echo -e "${YELLOW}⚠️  SECURITY WARNING: Checksum verification failed${NC}" >&2
            echo "" >&2
            echo -e "${YELLOW}💡 Solutions:${NC}" >&2
            echo "   1. DO NOT proceed - release may be compromised" >&2
            echo "   2. Verify checksum on upstream project website" >&2
            echo "   3. Contact project maintainers" >&2
            echo "" >&2
            ;;
        "docker_not_running")
            echo "" >&2
            echo -e "${YELLOW}💡 Solutions:${NC}" >&2
            echo "   1. Start Docker: sudo systemctl start docker" >&2
            echo "   2. Add user to docker group: sudo usermod -aG docker \$USER" >&2
            echo "   3. Log out and log back in" >&2
            echo "" >&2
            ;;
        "yq_not_installed")
            echo "" >&2
            echo -e "${YELLOW}💡 Solutions:${NC}" >&2
            echo "   1. Install yq: https://github.com/mikefarah/yq#install" >&2
            echo "   2. Ubuntu: sudo snap install yq" >&2
            echo "   3. macOS: brew install yq" >&2
            echo "" >&2
            ;;
    esac
    
    exit 1
}

# Simple error without exit (for non-fatal issues)
error_no_exit() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
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

# Progress message utilities
progress() {
    echo -e "${BLUE}→ $1${NC}"
}

step() {
    echo -e "${GREEN}• $1${NC}"
}

debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${YELLOW}🔍 DEBUG: $1${NC}" >&2
    fi
}

# Enhanced error with root cause analysis
error_with_cause() {
    local message="$1"
    local cause="$2"
    local solution="$3"
    local error_type="${4:-generic}"
    
    echo -e "${RED}❌ ERROR: $message${NC}" >&2
    
    if [ -n "$cause" ]; then
        echo "" >&2
        echo -e "${YELLOW}🔍 Root cause:${NC}" >&2
        echo "   $cause" >&2
    fi
    
    if [ -n "$solution" ]; then
        echo "" >&2
        echo -e "${YELLOW}💡 Solution:${NC}" >&2
        echo "   $solution" >&2
    fi
    
    # Add additional contextual help
    case "$error_type" in
        "404")
            echo "" >&2
            echo -e "${BLUE}📋 Related commands:${NC}" >&2
            echo "   curl -I https://api.github.com/repos/\$repo/releases/tags/\$version" >&2
            echo "   ./build.sh config.yaml \$version 1 --dry-run" >&2
            echo "" >&2
            ;;
        "403")
            echo "" >&2
            echo -e "${BLUE}📋 API Rate Limit Info:${NC}" >&2
            echo "   curl -s https://api.github.com/rate_limit" >&2
            echo "" >&2
            echo "   Unauthenticated requests: 60/hour" >&2
            echo "   Set GITHUB_TOKEN for higher limits" >&2
            echo "" >&2
            ;;
    esac
    
    exit 1
}

# Usage and help utilities
show_usage() {
    local script_name="$1"
    cat << EOF
Usage: $script_name <config-file> <version> <build-version> [architecture] [options]

Arguments:
  config-file     Path to multiarch-config.yaml
  version         Version to build (e.g., 0.9.3)
  build-version   Debian build version (e.g., 1)
  architecture    Target architecture or 'all' (default: all)

Options:
  --dry-run       Validate configuration without building
  --help, -h      Show this help message

Examples:
  $script_name config.yaml 2.35.0 1 arm64              # Build for arm64 only
  $script_name config.yaml 2.35.0 1 all                # Build for all architectures
  $script_name config.yaml 2.35.0 1 all --dry-run      # Validate first

Supported architectures: amd64, arm64, armel, armhf, i386, ppc64el, s390x, riscv64, loong64

Environment Variables:
  MAX_PARALLEL    Maximum concurrent builds (default: 2)
  PARALLEL_BUILDS Enable parallel builds (default: true)
  TELEMETRY_ENABLED Enable build telemetry (default: true)
  LINTIAN_CHECK   Enable lintian validation (default: false)
  DEBUG           Enable debug output (default: false)

Documentation: docs/
EOF
}