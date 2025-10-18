# Enhanced Build Telemetry Guide

The debian-multiarch-builder includes comprehensive build telemetry and metrics collection to help you monitor build performance, identify issues, and track regressions over time.

## Overview

The telemetry system collects the following metrics during builds:

- **Memory Usage**: Real-time memory monitoring with peak usage tracking
- **Network Statistics**: Download/upload bytes transferred during builds
- **Build Performance**: Duration, stages, and failure categorization
- **System Resources**: CPU cores, disk space, and system information
- **Performance Regression Detection**: Automatic detection of performance degradation

## Configuration

### Enable/Disable Telemetry

Telemetry is enabled by default but can be disabled:

```yaml
- name: Build packages
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: 'package.yaml'
    version: ${{ inputs.version }}
    build-version: ${{ inputs.build_version }}
    telemetry-enabled: false  # Disable telemetry
```

### Performance Baseline

Save successful builds as performance baselines for regression detection:

```yaml
- name: Build packages
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: 'package.yaml'
    version: ${{ inputs.version }}
    build-version: ${{ inputs.build_version }}
    save-baseline: true  # Save as baseline
```

## Telemetry Data Structure

### Build Session Metrics
```json
{
  "build_session": {
    "start_time": "2025-01-18T10:30:00+0530",
    "end_time": "2025-01-18T10:37:00+0530",
    "duration_seconds": 420,
    "hostname": "runner-linux-2",
    "os_info": "Linux 5.15.0-78-generic #85-Ubuntu",
    "cpu_cores": 2,
    "memory_total_mb": 8192,
    "disk_available_gb": 45
  }
}
```

### Memory Metrics
```json
{
  "memory_metrics": {
    "peak_usage_mb": 2048,
    "samples": [
      {"timestamp": 1642501800, "memory_mb": 512},
      {"timestamp": 1642501805, "memory_mb": 768}
    ]
  }
}
```

### Network Metrics
```json
{
  "network_metrics": {
    "bytes_downloaded": 52428800,
    "bytes_uploaded": 1048576,
    "interface": "eth0",
    "connection_count": 15
  }
}
```

### Build Metrics
```json
{
  "build_metrics": {
    "failure_category": "",
    "failure_stage": "",
    "failure_reason": "",
    "packages_built": 12,
    "packages_failed": 0,
    "build_stages": [
      {"name": "build_initialization", "status": "success", "duration": 2},
      {"name": "architecture_amd64", "status": "success", "duration": 180},
      {"name": "architecture_arm64", "status": "success", "duration": 220}
    ]
  }
}
```

### Performance Metrics
```json
{
  "performance_metrics": {
    "regressions_detected": [
      "Build duration increased by 25%",
      "Memory usage increased by 15%"
    ],
    "baseline_comparison": {
      "duration_diff_percent": 25,
      "memory_diff_percent": 15
    },
    "performance_score": 75
  }
}
```

## Build Summary Integration

Telemetry data is automatically included in the `build-summary.json`:

```json
{
  "package": "example-package",
  "version": "1.0.0",
  "telemetry": {
    "build_duration_seconds": 420,
    "peak_memory_mb": 2048,
    "network_downloaded_bytes": 52428800,
    "network_uploaded_bytes": 1048576,
    "failure_category": "",
    "performance_regressions": []
  }
}
```

## Failure Categorization

The telemetry system automatically categorizes build failures:

| Category | Description | Common Causes |
|----------|-------------|---------------|
| `network` | Network-related issues | Connection timeouts, download failures |
| `dependency` | Package dependency issues | Missing dependencies, apt failures |
| `architecture` | Cross-compilation issues | QEMU problems, toolchain issues |
| `compilation` | Build/compile failures | Compiler errors, make failures |
| `packaging` | Debian packaging issues | debhelper errors, lintian failures |
| `configuration` | Configuration problems | Invalid YAML, missing parameters |
| `permission` | Permission-related issues | Access denied, auth failures |
| `resource` | Resource exhaustion | Out of memory, disk space |
| `security` | Security/verification issues | Checksum failures, signature errors |
| `unknown` | Unclassified failures | Other issues |

## Performance Regression Detection

The system automatically detects performance regressions by comparing current builds with saved baselines:

### Regression Thresholds
- **Build Duration**: 20% increase triggers regression alert
- **Memory Usage**: 20% increase triggers regression alert

### Baseline Management
```bash
# Manually save current build as baseline
save_as_baseline

# Check for regressions in telemetry data
check_performance_regressions
```

## Telemetry Files

The telemetry system creates several files in the `.telemetry/` directory:

| File | Description |
|------|-------------|
| `build-telemetry.log` | Human-readable telemetry log |
| `metrics.json` | Complete telemetry data in JSON format |
| `baseline.json` | Saved performance baseline |
| `memory-samples.log` | Memory usage samples |
| `network-samples.log` | Network transfer samples |
| `build-stages.log` | Build stage timing and status |

## Usage Examples

### Basic Telemetry Usage

```yaml
name: Build with Telemetry

on:
  workflow_dispatch:
    inputs:
      version:
        required: true
      build_version:
        required: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build packages with telemetry
        uses: ranjithrajv/debian-multiarch-builder@v1
        with:
          config-file: 'package.yaml'
          version: ${{ inputs.version }}
          build-version: ${{ inputs.build_version }}
          telemetry-enabled: true

      - name: Upload telemetry data
        uses: actions/upload-artifact@v4
        with:
          name: telemetry-data
          path: .telemetry/
```

### Performance Monitoring

```yaml
- name: Build packages
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: 'package.yaml'
    version: ${{ inputs.version }}
    build-version: ${{ inputs.build_version }}
    save-baseline: true

- name: Check for regressions
  run: |
    if jq -e '.telemetry.performance_regressions | length > 0' build-summary.json; then
      echo "Performance regressions detected:"
      jq -r '.telemetry.performance_regressions[]' build-summary.json
      exit 1
    fi
```

### Custom Telemetry Processing

```yaml
- name: Process telemetry data
  run: |
    # Extract key metrics
    BUILD_TIME=$(jq -r '.telemetry.build_duration_seconds' build-summary.json)
    PEAK_MEMORY=$(jq -r '.telemetry.peak_memory_mb' build-summary.json)
    NETWORK_DOWN=$(jq -r '.telemetry.network_downloaded_bytes' build-summary.json)

    echo "Build completed in ${BUILD_TIME}s"
    echo "Peak memory usage: ${PEAK_MEMORY}MB"
    echo "Data downloaded: $(echo $NETWORK_DOWN | numfmt --to=iec)"

    # Alert on high memory usage
    if [ "$PEAK_MEMORY" -gt 4096 ]; then
      echo "::warning::High memory usage detected: ${PEAK_MEMORY}MB"
    fi
```

## Troubleshooting

### Telemetry Not Working

1. **Check if enabled**: Ensure `telemetry-enabled: true` in workflow
2. **Check permissions**: Ensure write access to workspace directory
3. **Check dependencies**: Verify `jq` is available for JSON processing

### High Memory Usage

1. **Monitor samples**: Check `.telemetry/memory-samples.log` for usage patterns
2. **Reduce parallelism**: Lower `max-parallel` setting
3. **Check system resources**: Verify runner has sufficient memory

### Network Issues

1. **Check interfaces**: Verify network interface detection
2. **Monitor connections**: Check connection counts in telemetry
3. **Validate downloads**: Ensure checksum verification is working

### Performance Regressions

1. **Compare baselines**: Check `.telemetry/baseline.json` for reference
2. **Analyze stages**: Review build stage timing in `.telemetry/build-stages.log`
3. **System changes**: Consider runner or dependency changes

## API Reference

### Telemetry Functions

```bash
# Initialize telemetry system
init_telemetry

# Record build stage start
record_build_stage "stage_name"

# Record build stage completion
record_build_stage_complete "stage_name" "success|failure|warning" "message"

# Record build failure
record_build_failure "stage" "reason" "error_code"

# Finalize telemetry collection
finalize_telemetry

# Get telemetry summary
get_telemetry_summary

# Save current build as baseline
save_as_baseline
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TELEMETRY_ENABLED` | Enable/disable telemetry | `true` |
| `SAVE_BASELINE` | Save build as baseline | `false` |
| `TELEMETRY_DIR` | Telemetry data directory | `.telemetry` |

## Best Practices

1. **Enable Telemetry**: Keep telemetry enabled for monitoring
2. **Save Baselines**: Regularly save baselines for regression detection
3. **Monitor Failures**: Use failure categorization to quickly identify issues
4. **Track Performance**: Monitor build duration and memory trends
5. **Automate Alerts**: Set up alerts for performance regressions
6. **Archive Data**: Keep telemetry data for historical analysis
7. **Integration**: Use telemetry data in CI/CD pipelines for automated decisions

## Advanced Usage

### Custom Telemetry Processing

```bash
# Process telemetry data with custom scripts
cat .telemetry/metrics.json | \
  jq '.memory_metrics.peak_usage_mb' | \
  awk '{if($1 > 2048) print "High memory usage: " $1 "MB"}'
```

### Performance Dashboards

Export telemetry data to monitoring systems:

```bash
# Export to Prometheus format
echo "build_duration_seconds $(jq -r '.build_session.duration_seconds' .telemetry/metrics.json)"
echo "peak_memory_mb $(jq -r '.memory_metrics.peak_usage_mb' .telemetry/metrics.json)"
```

### Integration with External Tools

```bash
# Send telemetry to external monitoring service
curl -X POST https://monitoring.example.com/api/metrics \
  -H "Content-Type: application/json" \
  -d @.telemetry/metrics.json
```