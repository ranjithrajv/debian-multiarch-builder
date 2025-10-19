# Debian Multi-Architecture Package Builder - Claude Reference

## Overview
This is a comprehensive GitHub Action for building Debian packages across multiple architectures from upstream GitHub releases. The action handles auto-discovery, parallel builds, lintian validation, telemetry, and automatic release creation.

## Key Components

### Action Configuration (`action.yml`)
- **Inputs**: config-file, version, build-version, architecture, max-parallel, lintian-check, telemetry-enabled, save-baseline
- **Outputs**: packages (list of generated .deb files)
- **Environment Variables**: CONFIG_FILE, VERSION, BUILD_VERSION, ARCHITECTURE, MAX_PARALLEL, LINTIAN_CHECK, TELEMETRY_ENABLED, SAVE_BASELINE, ACTION_PATH

### Core Scripts
- **build.sh**: Wrapper script that delegates to src/main.sh
- **src/main.sh**: Main build orchestration script with error handling and telemetry
- **src/lib/**: Modular library system for different functionalities

### Library Modules
- **utils.sh**: Common utility functions
- **config.sh**: Configuration parsing and validation
- **github-api.sh**: GitHub API interactions and release fetching
- **discovery.sh**: Auto-discovery of release assets and patterns
- **validation.sh**: Version and checksum validation
- **lintian.sh**: Lintian package validation
- **telemetry.sh**: Build metrics and performance monitoring
- **build.sh**: Core package building logic
- **orchestration.sh**: Parallel build orchestration
- **summary.sh**: Build summary generation

## Workflow Patterns

### Basic Workflow (`workflow-example.yml`)
```yaml
name: Build Package for Debian

on:
  workflow_dispatch:
    inputs:
      version: {required: true}
      build_version: {required: true}
      architecture: {type: choice, default: 'all'}

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ranjithrajv/debian-multiarch-builder@v1
        with:
          config-file: 'multiarch-config.yaml'
          version: ${{ inputs.version }}
          build-version: ${{ inputs.build_version }}
          architecture: ${{ inputs.architecture }}
      - uses: actions/upload-artifact@v4
        with:
          name: debian-packages
          path: '*.deb'

  release:
    if: github.ref == 'refs/heads/main'
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: debian-packages
      - uses: softprops/action-gh-release@v2
        with:
          draft: true
          files: '*.deb'
          name: ${{ inputs.version }}+${{ inputs.build_version }}
          tag_name: ${{ inputs.version }}
```

### Enhanced Workflow with Telemetry (`workflow-with-telemetry.yml`)
- Adds telemetry data upload
- Performance regression checking
- Enhanced release notes with build metrics
- Resource usage monitoring

### Lintian Integration (`workflow-with-lintian.yml`)
- Enables package quality validation
- Uploads build summary artifacts
- Configurable lintian checks

## Configuration Structure

### Main Config File (`multiarch-config.yaml`)
```yaml
package_name: "example"
github_repo: "owner/repo"
debian_version: 1
distributions: ["bookworm", "trixie"]
architectures:
  amd64: {}
  arm64: {}
```

### Defaults (`src/defaults.yaml`)
- **artifact_format**: tar.gz (default archive format)
- **binary_path**: "" (binaries in root)
- **parallel_builds**: Architecture and distribution parallelization
- **auto_discovery**: Release asset filtering and build preferences
- **checksum**: File patterns for verification
- **lintian**: Validation settings

## Build Process Flow

### 1. Initialization
- Parse configuration file
- Validate requirements and tools
- Initialize telemetry and lintian systems
- Record build start time

### 2. Version Validation
- Check if version exists in GitHub releases
- Fetch release information via GitHub API
- Validate availability before proceeding

### 3. Architecture Detection
- Get supported architectures from config
- Detect available architectures for current version
- Filter based on release asset availability

### 4. Build Orchestration
- **Parallel Mode**: Build multiple architectures concurrently
- **Sequential Mode**: Build one architecture at a time
- Track attempted, skipped, and successful builds

### 5. Package Generation
- Download and verify release assets
- Extract and prepare build environment
- Generate Debian packages using dockerized builds
- Run lintian validation if enabled

### 6. Results Processing
- Collect generated packages
- Generate build summary JSON
- Display resource usage metrics
- Cleanup temporary files

## Key Features

### Auto-Discovery
- Automatically detects release patterns for each architecture
- Filters release assets based on architecture-specific patterns
- Supports build type preferences (gnu > musl > linux)

### Parallel Builds
- **Architecture Parallel**: Build multiple architectures simultaneously
- **Distribution Parallel**: Build multiple distributions per architecture
- Configurable concurrency limits (2-4 recommended for GitHub runners)

### Telemetry and Monitoring
- Build duration tracking
- Memory and CPU usage monitoring
- Network transfer metrics
- Performance regression detection
- Baseline comparison capabilities

### Package Quality
- Lintian integration for policy validation
- Configurable error/warning thresholds
- Checksum verification of release assets
- Build summary generation

### Error Handling
- Comprehensive error trapping and reporting
- Failure categorization (transient vs permanent)
- Resource cleanup on errors
- Telemetry recording of failures

## Architecture Support

### Supported Architectures
- amd64, arm64, armel, armhf, i386, ppc64el, s390x, riscv64

### Distribution Support
- bookworm (Debian 12 - stable)
- trixie (Debian 13 - testing)
- forky (Debian 14 - experimental)
- sid (unstable)

### Build Environment
- Docker-based isolated builds
- Multi-architecture container support
- Cross-compilation capabilities

## File Structure Patterns

### Generated Packages
- `{package_name}_{version}+{dist}_{arch}.deb`

### Build Artifacts
- `build-summary.json`: Comprehensive build metrics
- `.telemetry/`: Telemetry data files
- `build-summary-*.json`: Version-specific summaries

### Configuration Files
- `multiarch-config.yaml`: Main project configuration
- `src/defaults.yaml`: System defaults
- `examples/*.yaml`: Example configurations

## Common Issues and Solutions

### Version Not Found
- Check GitHub releases for actual available versions
- Ensure correct version format (e.g., "v1.0.0" vs "1.0.0")

### Architecture Not Available
- Release assets may not exist for all architectures
- Check project's GitHub releases page
- May need to skip unavailable architectures

### Memory Issues
- Reduce `max-parallel` setting
- Use larger GitHub runners if needed
- Monitor telemetry for memory usage

### Lintian Errors
- Check `build-summary.json` for specific lintian findings
- Configure suppressions for known issues
- Fix package structure problems

## Performance Optimization

### Parallel Build Settings
- GitHub Actions: 2-4 concurrent builds recommended
- Larger runners can handle more parallelism
- Monitor memory usage to avoid OOM

### Caching Strategy
- Download caching between builds
- Docker layer caching
- GitHub API response caching

### Resource Monitoring
- Track peak memory usage
- Monitor CPU utilization
- Network transfer optimization

## Integration Examples

### CI/CD Pipeline
```yaml
- name: Build and Test
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: config.yaml
    version: ${{ env.VERSION }}
    build-version: ${{ env.BUILD_VERSION }}
    lintian-check: true
    telemetry-enabled: true
```

### Release Automation
- Automatic draft release creation
- Enhanced release notes with telemetry
- Artifact upload and management

### Quality Gates
- Lintian validation failures block release
- Performance regression detection
- Build success rate requirements

## Debugging and Troubleshooting

### Build Logs
- Detailed progress tracking
- Architecture availability detection
- Resource usage monitoring

### Telemetry Data
- Build duration analysis
- Memory usage patterns
- Network transfer metrics

### Common Debugging Steps
1. Check version exists in GitHub releases
2. Verify configuration file syntax
3. Monitor resource usage during builds
4. Review lintian validation results
5. Analyze build summary JSON

## Testing and Validation

### Testing Workflow Changes
To test and validate changes made to this GitHub workflow, you need to trigger test workflows from the related `../uv-debian` repository using the GitHub CLI:

```bash
# Navigate to uv-debian directory (relative to this project)
cd ../uv-debian

# Trigger a test workflow using gh CLI
gh workflow run "Build Package for Debian" \
  --field version="1.0.0" \
  --field build_version="1" \
  --field architecture="all"

# Monitor the workflow run
gh run view --watch

# Check workflow status and logs
gh run list
gh run view <run-id>
```

## GitHub Actions Environment & Billing

### Default Configuration
- **Plan**: GitHub Actions Free Plan (default)
- **Runner**: Linux Ubuntu runners (1x minute multiplier)
- **Monthly Allowance**: 2,000 minutes for free plan
- **Storage**: 500 MB storage allowance

### Runner Specifications (Free Plan)
- **Default**: Standard Linux runners (2-core, 7GB RAM, 14GB disk)
- **OS**: Ubuntu (latest, 22.04, 20.04)
- **Optimization**: Auto-detected and optimized for CI environment
- **Parallel Jobs**: Resource-aware (typically 2 concurrent jobs for standard runners)

### Resource Optimization
- **Auto-detection**: System detects GitHub Actions environment automatically
- **Parallel Limits**: Adjusted based on available resources (2 cores, 7GB RAM)
- **Graceful Degradation**: Reduces parallel jobs if resources become constrained
- **CI Overhead**: Reserves 1 CPU core and 1GB RAM for CI infrastructure

### Cost Considerations
- **Public Repositories**: Free minutes apply
- **Private Repositories**: Free plan includes 2,000 minutes/month
- **Linux Multiplier**: 1x (most cost-effective)
- **Standard Runners**: Included in free allowance
- **Large Runners**: Always charged, not available on free plan

### Performance Recommendations
- **Standard Runners**: Use `max_parallel: 2` for optimal performance
- **Resource Limits**: Monitor memory usage during builds
- **Parallel Builds**: Architecture and distribution parallelization enabled
- **CI Optimization**: Automatic resource detection and adjustment

### Validation Steps
1. **Local Testing**: Test changes in a development branch first
2. **Integration Testing**: Use uv-debian repository to validate end-to-end functionality
3. **Parallel Build Testing**: Verify concurrent builds work correctly
4. **Architecture Testing**: Test all supported architectures
5. **Lintian Validation**: Ensure package quality checks pass

### Test Scenarios
- **Basic Build**: Single architecture, default settings
- **Multi-Arch Build**: All architectures, parallel execution
- **Telemetry Testing**: Enable metrics collection and baseline comparison
- **Error Handling**: Test failure scenarios and recovery
- **Performance Testing**: Monitor resource usage and build times

## Security Considerations

### Checksum Verification
- Automatic SHA256 verification
- Configurable checksum file patterns
- GitHub API integrity checks

### Build Isolation
- Docker-based sandboxed builds
- Temporary file cleanup
- No persistent state between builds

### Dependency Management
- Minimal dependency installation
- Secure package sources
- Regular base image updates