# Build Summary

The action automatically generates a `build-summary.json` file containing comprehensive build metadata. Here's a detailed explanation of each field:

*   `package`: The name of the package.
*   `version`: The version of the software being built.
*   `build_version`: The Debian build version.
*   `full_version`: The full version string, in the format `version-build_version`.
*   `github_repo`: The GitHub repository from which the software was downloaded.
*   `architectures`: A list of the architectures for which the package was built.
*   `distributions`: A list of the distributions for which the package was built.
*   `total_packages`: The total number of packages that were built.
*   `total_size_bytes`: The total size of all the packages, in bytes.
*   `total_size_human`: The total size of all the packages, in a human-readable format (e.g., "315 MB").
*   `build_duration_seconds`: The duration of the build, in seconds.
*   `build_start`: The timestamp of when the build started.
*   `build_end`: The timestamp of when the build ended.
*   `parallel_builds`: A boolean value indicating whether parallel builds were enabled.
*   `max_parallel`: The maximum number of parallel builds.
*   `packages`: A list of the packages that were built, with their names and sizes.
*   `lintian`: A list of the Lintian results for each package.
*   `telemetry`: Enhanced build metrics including memory usage, network statistics, and performance data.

**Example output:**
```json
{
  "package": "uv",
  "version": "0.9.3",
  "build_version": "1",
  "full_version": "0.9.3-1",
  "github_repo": "astral-sh/uv",
  "architectures": ["amd64", "arm64", "armhf"],
  "distributions": ["bookworm", "trixie", "forky", "sid"],
  "total_packages": 12,
  "total_size_bytes": 330301440,
  "total_size_human": "315 MB",
  "build_duration_seconds": 420,
  "build_start": "2025-10-17T10:30:00+0530",
  "build_end": "2025-10-17T10:37:00+0530",
  "parallel_builds": true,
  "max_parallel": 2,
  "packages": [
    {"name": "uv_0.9.3-1+bookworm_amd64.deb", "size": 12845632},
    {"name": "uv_0.9.3-1+bookworm_arm64.deb", "size": 11932456}
  ],
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

**New fields:**
- `total_size_bytes`: Total size of all packages in bytes
- `total_size_human`: Human-readable total size (e.g., "315 MB")
- `telemetry`: Enhanced build metrics section with telemetry data

**Use cases:**
- **Automated artifact upload** - Parse package list for upload to apt repositories
- **Release notes generation** - Extract version and package details
- **Build monitoring** - Track build duration and success rates
- **Performance analysis** - Monitor memory usage and build performance over time
- **CI/CD integration** - Use in GitHub Actions workflows for downstream jobs
- **Regression detection** - Identify performance degradations using telemetry data

**Example GitHub Actions integration:**
```yaml
- name: Build packages
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: 'package.yaml'
    version: ${{ inputs.version }}
    build-version: ${{ inputs.build_version }}

- name: Parse build summary
  run: |
    PACKAGE_COUNT=$(jq '.total_packages' build-summary.json)
    BUILD_TIME=$(jq '.build_duration_seconds' build-summary.json)
    PEAK_MEMORY=$(jq -r '.telemetry.peak_memory_mb // "N/A"' build-summary.json)
    echo "Built $PACKAGE_COUNT packages in $BUILD_TIME seconds"
    echo "Peak memory usage: ${PEAK_MEMORY}MB"
```
