#!/bin/bash

# GitHub Actions Optimization and CI Environment Detection
# Provides auto-detection of runner specifications and resource-based optimization

# CI environment detection variables
export CI_ENVIRONMENT detected=false
export RUNNER_TYPE="unknown"
export RUNNER_CPU_CORES=0
export RUNNER_MEMORY_GB=0
export RUNNER_DISK_GB=0
export IS_GITHUB_ACTIONS=false
export IS_CI_ENVIRONMENT=false
export OPTIMIZED_PARALLEL_JOBS=2
export RESOURCE_BASED_LIMITS=true

# GitHub Actions runner specifications
declare -A GITHUB_RUNNER_SPECS=(
    ["ubuntu-latest"]="2_core_7gb"
    ["ubuntu-22.04"]="2_core_7gb"
    ["ubuntu-20.04"]="2_core_7gb"
    ["ubuntu-24.04"]="4_core_16gb"
    ["windows-latest"]="2_core_7gb"
    ["windows-2022"]="2_core_7gb"
    ["windows-2019"]="2_core_7gb"
    ["macos-latest"]="3_core_14gb"
    ["macos-13"]="3_core_14gb"
    ["macos-14"]="4_core_16gb"
    ["macos-15"]="4_core_16gb"
)

# Runner specifications mapping (cores_memory_gb_disk_gb)
declare -A RUNNER_SPECIFICATIONS=(
    ["2_core_7gb"]="2:7:14"
    ["4_core_16gb"]="4:16:100"
    ["8_core_32gb"]="8:32:200"
    ["16_core_64gb"]="16:64:400"
    ["32_core_128gb"]="32:128:800"
    ["large_runner_linux"]="4_core_16gb"
    ["large_runner_windows"]="8_core_32gb"
    ["large_runner_macos"]="4_core_16gb"
)

# Resource-based parallel job limits
declare -A RESOURCE_PARALLEL_LIMITS=(
    ["1:2"]="1"      # 1 core, 2GB RAM - 1 job
    ["1:4"]="1"      # 1 core, 4GB RAM - 1 job
    ["2:4"]="1"      # 2 cores, 4GB RAM - 1 job
    ["2:7"]="2"      # 2 cores, 7GB RAM - 2 jobs (GitHub Actions standard)
    ["2:8"]="2"      # 2 cores, 8GB RAM - 2 jobs
    ["4:8"]="2"      # 4 cores, 8GB RAM - 2 jobs
    ["4:16"]="4"     # 4 cores, 16GB RAM - 4 jobs
    ["4:32"]="4"     # 4 cores, 32GB RAM - 4 jobs
    ["8:16"]="4"     # 8 cores, 16GB RAM - 4 jobs
    ["8:32"]="6"     # 8 cores, 32GB RAM - 6 jobs
    ["8:64"]="8"     # 8 cores, 64GB RAM - 8 jobs
    ["16:32"]="6"    # 16 cores, 32GB RAM - 6 jobs
    ["16:64"]="12"   # 16 cores, 64GB RAM - 12 jobs
    ["16:128"]="16"  # 16 cores, 128GB RAM - 16 jobs
    ["32:64"]="12"   # 32 cores, 64GB RAM - 12 jobs
    ["32:128"]="24"  # 32 cores, 128GB RAM - 24 jobs
)

# Detect GitHub Actions environment
detect_github_actions() {
    if [ -n "$GITHUB_ACTIONS" ] && [ "$GITHUB_ACTIONS" = "true" ]; then
        IS_GITHUB_ACTIONS=true
        IS_CI_ENVIRONMENT=true
        CI_ENVIRONMENT="github-actions"

        # Detect runner image and specs
        local runner_image="${RUNNER_OS:-unknown}-${RUNNER_ARCH:-unknown}"

        case "${RUNNER_OS:-unknown}" in
            "Linux")
                detect_linux_runner_specs
                ;;
            "Windows")
                detect_windows_runner_specs
                ;;
            "macOS")
                detect_macos_runner_specs
                ;;
            *)
                RUNNER_TYPE="unknown-github-runner"
                detect_system_resources_fallback
                ;;
        esac

        return 0
    else
        return 1
    fi
}

# Detect Linux runner specifications
detect_linux_runner_specs() {
    local runner_name="${RUNNER_NAME:-unknown}"

    # Check for known GitHub Actions runner patterns
    if echo "$runner_name" | grep -qi "ubuntu-latest\|ubuntu-22.04\|ubuntu-20.04"; then
        RUNNER_TYPE="github-actions-ubuntu-standard"
        RUNNER_CPU_CORES=2
        RUNNER_MEMORY_GB=7
        RUNNER_DISK_GB=14
    elif echo "$runner_name" | grep -qi "ubuntu-24.04"; then
        RUNNER_TYPE="github-actions-ubuntu-24.04"
        RUNNER_CPU_CORES=4
        RUNNER_MEMORY_GB=16
        RUNNER_DISK_GB=100
    elif echo "$runner_name" | grep -qi "large\|4-core\|8-core"; then
        # GitHub Actions large runners
        if echo "$runner_name" | grep -qi "8-core"; then
            RUNNER_TYPE="github-actions-large-linux-8core"
            RUNNER_CPU_CORES=8
            RUNNER_MEMORY_GB=32
            RUNNER_DISK_GB=200
        else
            RUNNER_TYPE="github-actions-large-linux-4core"
            RUNNER_CPU_CORES=4
            RUNNER_MEMORY_GB=16
            RUNNER_DISK_GB=100
        fi
    else
        detect_system_resources_fallback
    fi
}

# Detect Windows runner specifications
detect_windows_runner_specs() {
    local runner_name="${RUNNER_NAME:-unknown}"

    if echo "$runner_name" | grep -qi "windows-latest\|windows-2022\|windows-2019"; then
        RUNNER_TYPE="github-actions-windows-standard"
        RUNNER_CPU_CORES=2
        RUNNER_MEMORY_GB=7
        RUNNER_DISK_GB=100
    elif echo "$runner_name" | grep -qi "large\|4-core\|8-core"; then
        if echo "$runner_name" | grep -qi "8-core"; then
            RUNNER_TYPE="github-actions-large-windows-8core"
            RUNNER_CPU_CORES=8
            RUNNER_MEMORY_GB=32
            RUNNER_DISK_GB=200
        else
            RUNNER_TYPE="github-actions-large-windows-4core"
            RUNNER_CPU_CORES=4
            RUNNER_MEMORY_GB=16
            RUNNER_DISK_GB=100
        fi
    else
        detect_system_resources_fallback
    fi
}

# Detect macOS runner specifications
detect_macos_runner_specs() {
    local runner_name="${RUNNER_NAME:-unknown}"

    if echo "$runner_name" | grep -qi "macos-13\|macos-latest"; then
        RUNNER_TYPE="github-actions-macos-13"
        RUNNER_CPU_CORES=3
        RUNNER_MEMORY_GB=14
        RUNNER_DISK_GB=50
    elif echo "$runner_name" | grep -qi "macos-14"; then
        RUNNER_TYPE="github-actions-macos-14"
        RUNNER_CPU_CORES=4
        RUNNER_MEMORY_GB=16
        RUNNER_DISK_GB=50
    elif echo "$runner_name" | grep -qi "macos-15\|macos-14-large"; then
        RUNNER_TYPE="github-actions-macos-large"
        RUNNER_CPU_CORES=4
        RUNNER_MEMORY_GB=16
        RUNNER_DISK_GB=100
    else
        detect_system_resources_fallback
    fi
}

# Fallback: detect system resources directly
detect_system_resources_fallback() {
    RUNNER_TYPE="detected-system-resources"

    # Detect CPU cores
    if command -v nproc >/dev/null 2>&1; then
        RUNNER_CPU_CORES=$(nproc)
    elif [ -f /proc/cpuinfo ]; then
        RUNNER_CPU_CORES=$(grep -c processor /proc/cpuinfo)
    elif command -v sysctl >/dev/null 2>&1; then
        RUNNER_CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "2")
    else
        RUNNER_CPU_CORES=2  # Conservative fallback
    fi

    # Detect memory in GB
    if command -v free >/dev/null 2>&1; then
        local memory_kb=$(free -t | awk '/^Total:/{print $2}')
        RUNNER_MEMORY_GB=$((memory_kb / 1024 / 1024))
    elif [ -f /proc/meminfo ]; then
        local memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        RUNNER_MEMORY_GB=$((memory_kb / 1024 / 1024))
    elif command -v sysctl >/dev/null 2>&1; then
        local memory_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "4294967296")
        RUNNER_MEMORY_GB=$((memory_bytes / 1024 / 1024 / 1024))
    else
        RUNNER_MEMORY_GB=4  # Conservative fallback
    fi

    # Detect disk space in GB
    if command -v df >/dev/null 2>&1; then
        RUNNER_DISK_GB=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    else
        RUNNER_DISK_GB=20  # Conservative fallback
    fi
}

# Detect other CI environments (GitLab, Azure DevOps, etc.)
detect_other_ci_environments() {
    # GitLab CI
    if [ -n "$GITLAB_CI" ] && [ "$GITLAB_CI" = "true" ]; then
        CI_ENVIRONMENT="gitlab-ci"
        IS_CI_ENVIRONMENT=true
        detect_system_resources_fallback
        return 0
    fi

    # Azure DevOps
    if [ -n "$TF_BUILD" ] && [ "$TF_BUILD" = "true" ]; then
        CI_ENVIRONMENT="azure-devops"
        IS_CI_ENVIRONMENT=true
        detect_system_resources_fallback
        return 0
    fi

    # Jenkins
    if [ -n "$JENKINS_URL" ]; then
        CI_ENVIRONMENT="jenkins"
        IS_CI_ENVIRONMENT=true
        detect_system_resources_fallback
        return 0
    fi

    # CircleCI
    if [ -n "$CIRCLECI" ] && [ "$CIRCLECI" = "true" ]; then
        CI_ENVIRONMENT="circleci"
        IS_CI_ENVIRONMENT=true
        detect_system_resources_fallback
        return 0
    fi

    # Travis CI
    if [ -n "$TRAVIS" ] && [ "$TRAVIS" = "true" ]; then
        CI_ENVIRONMENT="travis-ci"
        IS_CI_ENVIRONMENT=true
        detect_system_resources_fallback
        return 0
    fi

    # Bitbucket Pipelines
    if [ -n "$BITBUCKET_BUILD_NUMBER" ]; then
        CI_ENVIRONMENT="bitbucket-pipelines"
        IS_CI_ENVIRONMENT=true
        detect_system_resources_fallback
        return 0
    fi

    return 1
}

# Calculate optimal parallel jobs based on available resources
calculate_optimal_parallel_jobs() {
    local memory_per_job=2048  # 2GB RAM per job baseline
    local cpu_per_job=1        # 1 CPU core per job baseline
    local disk_per_job=5       # 5GB disk per job baseline

    # Calculate memory-based limit
    local memory_based_limit=$((${RUNNER_MEMORY_GB:-0} * 1024 / memory_per_job))

    # Calculate CPU-based limit
    local cpu_based_limit=$((${RUNNER_CPU_CORES:-0} / cpu_per_job))

    # Calculate disk-based limit (conservative)
    local disk_based_limit=$((${RUNNER_DISK_GB:-0} / disk_per_job))

    # Use the most restrictive limit
    local calculated_limit=$memory_based_limit
    if [ $cpu_based_limit -lt $calculated_limit ]; then
        calculated_limit=$cpu_based_limit
    fi
    if [ $disk_based_limit -lt $calculated_limit ]; then
        calculated_limit=$disk_based_limit
    fi

    # Ensure at least 1 job
    if [ $calculated_limit -lt 1 ]; then
        calculated_limit=1
    fi

    # Apply safety margins for CI environments
    if [ "$IS_CI_ENVIRONMENT" = "true" ]; then
        # Reduce by 1 to leave room for CI overhead
        calculated_limit=$((calculated_limit - 1))
        if [ $calculated_limit -lt 1 ]; then
            calculated_limit=1
        fi
    fi

    # Apply maximum limits to prevent resource exhaustion
    if [ $calculated_limit -gt 8 ]; then
        calculated_limit=8
    fi

    OPTIMIZED_PARALLEL_JOBS=$calculated_limit
}

# Apply resource-based optimizations to configuration
apply_ci_optimizations() {
    local current_max_parallel="$1"

    if [ "$RESOURCE_BASED_LIMITS" != "true" ]; then
        echo "$current_max_parallel"
        return 0
    fi

    # Use resource-based calculation
    calculate_optimal_parallel_jobs

    # Respect user's maximum if it's lower than our calculated optimum
    if [ "$current_max_parallel" -gt 0 ] && [ "$current_max_parallel" -lt "$OPTIMIZED_PARALLEL_JOBS" ]; then
        echo "$current_max_parallel"
    else
        echo "$OPTIMIZED_PARALLEL_JOBS"
    fi
}

# Initialize CI environment detection and optimization
init_ci_optimization() {
    # Reset detection state
    detected=false
    CI_ENVIRONMENT="local"
    RUNNER_TYPE="local-system"

    # Try GitHub Actions first
    if detect_github_actions; then
        detected=true
        info "GitHub Actions environment detected"
        info "Runner type: $RUNNER_TYPE"
        info "Detected specs: ${RUNNER_CPU_CORES} cores, ${RUNNER_MEMORY_GB}GB RAM, ${RUNNER_DISK_GB}GB disk"
    else
        # Try other CI environments
        if detect_other_ci_environments; then
            detected=true
            info "CI environment detected: $CI_ENVIRONMENT"
            info "Detected specs: ${RUNNER_CPU_CORES} cores, ${RUNNER_MEMORY_GB}GB RAM, ${RUNNER_DISK_GB}GB disk"
        fi
    fi

    if [ "$detected" = "false" ]; then
        info "No CI environment detected, using local system detection"
        detect_system_resources_fallback
        RESOURCE_BASED_LIMITS=false  # Don't enforce limits on local systems
    fi

    # Calculate optimal parallel jobs
    calculate_optimal_parallel_jobs

    info "Resource-based optimization: ${OPTIMIZED_PARALLEL_JOBS} parallel jobs recommended"

    # Export variables for other modules
    export CI_ENVIRONMENT RUNNER_TYPE RUNNER_CPU_CORES RUNNER_MEMORY_GB RUNNER_DISK_GB
    export IS_GITHUB_ACTIONS IS_CI_ENVIRONMENT OPTIMIZED_PARALLEL_JOBS RESOURCE_BASED_LIMITS detected
}

# Generate CI environment report
generate_ci_environment_report() {
    cat << EOF
🖥️  CI ENVIRONMENT REPORT
==========================================
Environment: $CI_ENVIRONMENT
Runner Type: $RUNNER_TYPE
GitHub Actions: $IS_GITHUB_ACTIONS
CI Environment: $IS_CI_ENVIRONMENT
Resource Detection: $detected

System Resources:
- CPU Cores: $RUNNER_CPU_CORES
- Memory: ${RUNNER_MEMORY_GB}GB
- Disk: ${RUNNER_DISK_GB}GB

Optimizations:
- Resource-based Limits: $RESOURCE_BASED_LIMITS
- Optimal Parallel Jobs: $OPTIMIZED_PARALLEL_JOBS
- Recommended max_parallel: $OPTIMIZED_PARALLEL_JOBS

Performance Recommendations:
EOF

    # Add specific recommendations based on resources
    if [ "$IS_CI_ENVIRONMENT" = "true" ]; then
        echo "- CI Environment detected: Using conservative resource allocation"
        echo "- Overhead reserved: 1 CPU core and 1GB RAM for CI infrastructure"
    fi

    if [ $RUNNER_MEMORY_GB -lt 4 ]; then
        echo "- ⚠️  Low memory detected: Consider using larger runners for complex builds"
    fi

    if [ $RUNNER_CPU_CORES -lt 2 ]; then
        echo "- ⚠️  Single-core system: Sequential builds recommended"
    fi

    if [ $RUNNER_DISK_GB -lt 10 ]; then
        echo "- ⚠️  Limited disk space: Monitor disk usage during builds"
    fi

    echo ""
}

# Apply graceful degradation for limited resources
apply_graceful_degradation() {
    local requested_jobs="$1"
    local available_memory_mb="$2"
    local available_cores="$3"

    # Minimum resource requirements per parallel job
    local min_memory_per_job=1024  # 1GB RAM minimum
    local min_cores_per_job=1      # 1 CPU core minimum

    # Calculate maximum jobs based on available resources
    local memory_limit=$((available_memory_mb / min_memory_per_job))
    local core_limit=$((available_cores / min_cores_per_job))

    # Apply the more restrictive limit
    local sustainable_jobs=$memory_limit
    if [ $core_limit -lt $sustainable_jobs ]; then
        sustainable_jobs=$core_limit
    fi

    # Ensure at least 1 job can run
    if [ $sustainable_jobs -lt 1 ]; then
        sustainable_jobs=1
    fi

    # If requested jobs exceed sustainable limits, warn and adjust
    if [ $requested_jobs -gt $sustainable_jobs ]; then
        warning "Resource constraints detected: Reducing parallel jobs from $requested_jobs to $sustainable_jobs"
        warning "Available: ${available_cores} cores, ${available_memory_mb}MB RAM"
        warning "Required per job: ${min_cores_per_job} core, ${min_memory_per_job}MB RAM minimum"

        # Log resource preservation measures
        info "Graceful degradation: Preserving system stability and preventing resource exhaustion"

        echo "$sustainable_jobs"
    else
        echo "$requested_jobs"
    fi
}

# Validate build environment readiness
validate_build_environment() {
    local issues=()

    # Check minimum system requirements
    if [ $RUNNER_MEMORY_GB -lt 2 ]; then
        issues+=("Insufficient memory: ${RUNNER_MEMORY_GB}GB (minimum: 2GB recommended)")
    fi

    if [ $RUNNER_CPU_CORES -lt 1 ]; then
        issues+=("Insufficient CPU cores: ${RUNNER_CPU_CORES} (minimum: 1 core required)")
    fi

    if [ $RUNNER_DISK_GB -lt 5 ]; then
        issues+=("Insufficient disk space: ${RUNNER_DISK_GB}GB (minimum: 5GB recommended)")
    fi

    # Check for Docker availability in CI environments
    if [ "$IS_CI_ENVIRONMENT" = "true" ] && ! command -v docker >/dev/null 2>&1; then
        issues+=("Docker not available in CI environment")
    fi

    # Report any issues
    if [ ${#issues[@]} -gt 0 ]; then
        warning "Build environment validation warnings:"
        for issue in "${issues[@]}"; do
            warning "  • $issue"
        done
        return 1
    else
        info "Build environment validation passed"
        return 0
    fi
}

# Export functions for use in other modules
export -f detect_github_actions
export -f detect_other_ci_environments
export -f detect_system_resources_fallback
export -f calculate_optimal_parallel_jobs
export -f apply_ci_optimizations
export -f init_ci_optimization
export -f generate_ci_environment_report
export -f apply_graceful_degradation
export -f validate_build_environment