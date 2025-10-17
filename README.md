# Debian Multi-Architecture Package Builder

A reusable GitHub Action for building Debian packages across multiple architectures from upstream releases. This action simplifies the process of creating multi-architecture Debian packages for projects distributed via GitHub releases.

## Features

- Build Debian packages for multiple architectures: amd64, arm64, armel, armhf, i386, ppc64el, s390x, riscv64
- Support for multiple Debian distributions: Bookworm, Trixie, Forky, Sid
- **Multi-level parallelization** - 75-80% faster with parallel architecture + distribution builds
- **Download caching** - Download once per architecture, reuse for all distributions
- **Checksum verification** - Automatic SHA256 verification for download integrity and security
- **Auto-discovery** - Automatically discover release patterns from GitHub releases
- **Build summary JSON** - Automatic metadata export for CI/CD integration and automation
- Configuration-driven approach using YAML
- Distribution-specific architecture support (e.g., i386 for Bookworm only, riscv64 for Trixie+)
- Docker-based builds for reproducibility
- Single command to build all architectures or specific ones
- Comprehensive error messages with troubleshooting hints

## Prerequisites

Your repository needs the following structure:

```
your-package-debian/
├── .github/
│   └── workflows/
│       └── release.yml          # Your workflow file
├── output/
│   ├── DEBIAN/
│   │   └── control              # Package control file
│   ├── copyright                # Copyright information
│   ├── changelog.Debian         # Changelog file
│   └── README.md                # Optional documentation
├── multiarch-config.yaml        # Multi-arch configuration
└── Dockerfile                   # (Not needed - provided by action)
```

## Quick Start

### 1. Create Configuration File

Create a `multiarch-config.yaml` in your repository root:

**Option A: Auto-discovery (Recommended)**
```yaml
package_name: lazygit
github_repo: jesseduffield/lazygit
artifact_format: tar.gz

debian_distributions:
  - bookworm
  - trixie
  - forky
  - sid

# Simple list - release patterns auto-discovered from GitHub
architectures:
  - amd64
  - arm64
  - armhf
```

**Option B: Manual patterns (Advanced)**
```yaml
package_name: lazygit
github_repo: jesseduffield/lazygit
artifact_format: tar.gz

debian_distributions:
  - bookworm
  - trixie
  - forky
  - sid

# Explicit patterns for full control
architectures:
  amd64:
    release_pattern: "lazygit_{version}_Linux_x86_64.tar.gz"
  arm64:
    release_pattern: "lazygit_{version}_Linux_arm64.tar.gz"
  armhf:
    release_pattern: "lazygit_{version}_Linux_armv7.tar.gz"
```

### 2. Create or Update Workflow

Create `.github/workflows/release.yml`:

```yaml
name: Build Package for Debian

on:
  workflow_dispatch:
    inputs:
      version:
        description: The version of the software to build
        type: string
        required: true
      build_version:
        description: The build version
        type: string
        required: true
      architecture:
        description: Architecture to build
        type: choice
        default: 'all'
        options:
          - 'all'
          - 'amd64'
          - 'arm64'
          - 'armel'
          - 'armhf'
          - 'i386'
          - 'ppc64el'
          - 's390x'
          - 'riscv64'

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build packages
        uses: ranjithrajv/debian-multiarch-builder@v1
        with:
          config-file: 'multiarch-config.yaml'
          version: ${{ inputs.version }}
          build-version: ${{ inputs.build_version }}
          architecture: ${{ inputs.architecture }}

      - uses: actions/upload-artifact@v4
        with:
          name: debian-packages
          path: '*.deb'
```

### 3. Update DEBIAN/control File

Your `output/DEBIAN/control` should use placeholders:

```
Section: utils
Priority: optional
Maintainer: Your Name <your.email@example.com>
Homepage: https://github.com/GITHUB_REPO
Package: PACKAGE_NAME
Version: VERSION-BUILD_VERSION+DIST
Architecture: SUPPORTED_ARCHITECTURES
Description: Your package description here
```

Placeholders that will be replaced:
- `PACKAGE_NAME` - from config
- `VERSION` - from workflow input
- `BUILD_VERSION` - from workflow input
- `DIST` - current Debian distribution
- `SUPPORTED_ARCHITECTURES` - current architecture
- `GITHUB_REPO` - from config

### 4. Update changelog.Debian

Your `output/changelog.Debian` should use placeholders:

```
PACKAGE_NAME (FULL_VERSION) DIST; urgency=medium

  * New upstream release

 -- Your Name <your.email@example.com>  Mon, 01 Jan 2024 00:00:00 +0000
```

## Performance

### Multi-Level Parallelization

The action implements **two levels of parallelization** for maximum performance:

1. **Parallel Architecture Builds** - Multiple architectures build concurrently (configurable)
2. **Parallel Distribution Builds** - All distributions build concurrently within each architecture (automatic)
3. **Download Caching** - Download once per architecture, reuse for all distributions

### Performance Features

- **Default behavior:** 2 concurrent architecture builds, unlimited concurrent distributions
- **Time savings:** 70-80% faster than fully sequential builds
- **Example:** Building 8 architectures × 4 distributions (32 packages):
  - Sequential: ~30 minutes
  - Current optimizations: ~5-7 minutes

### Configuration

```yaml
# Optional: customize parallel architecture build settings
parallel_builds: true    # Default: true (enabled)
max_parallel: 2          # Default: 2 (concurrent architecture builds)
```

**Note:** Distribution parallelization is always enabled and cannot be disabled.

**Recommendations:**
- GitHub Actions standard runners: `max_parallel: 2` (2 CPU cores)
- Self-hosted runners with 4+ cores: `max_parallel: 4`
- Sequential architecture builds: Set `parallel_builds: false` (still builds distributions in parallel)

### Performance Comparison

| Configuration | 8 Archs × 4 Dists (32 packages) | Time Savings |
|---------------|----------------------------------|--------------|
| Fully Sequential | ~30 minutes | baseline |
| Parallel Archs (2) Only | ~15 minutes | 50% faster |
| Parallel Archs (2) + Parallel Dists | ~5-7 minutes | 75-80% faster |
| Parallel Archs (4) + Parallel Dists | ~3-4 minutes | 85-90% faster |

**Key Optimizations:**
- **Download Caching**: Previously downloaded 4× per architecture (once per distribution), now downloads once
- **Parallel Distributions**: Previously built distributions sequentially, now builds all 4 simultaneously
- **Combined Effect**: Reduces per-architecture build time from ~4 minutes to ~1 minute

## Auto-Discovery

The action can automatically discover release patterns from GitHub releases, eliminating the need to manually configure `release_pattern` for each architecture.

### How It Works

1. **Fetches release assets** from GitHub API for the specified version
2. **Matches assets** to architectures using common naming patterns
3. **Prefers gnu builds** when available (native to Debian, better performance)
4. **Falls back to musl builds** if gnu not available

### Supported Pattern Matching

| Debian Arch | Matches Upstream Patterns |
|-------------|---------------------------|
| amd64       | x86_64, amd64, x64 |
| arm64       | aarch64, arm64 |
| armel       | arm-, armeabi |
| armhf       | armv7, armhf, arm-.*gnueabihf |
| i386        | i686, i386, x86 |
| ppc64el     | powerpc64le, ppc64le |
| s390x       | s390x |
| riscv64     | riscv64gc, riscv64 |

### When to Use Manual Patterns

Use manual `release_pattern` configuration when:
- Upstream uses non-standard naming conventions
- You need to select a specific variant (e.g., gnu vs musl)
- Release assets don't follow predictable patterns
- You want explicit control over which assets are used

### Example Comparison

**Auto-discovery:**
```yaml
architectures:
  - amd64
  - arm64
  - armhf
```
Discovers: `uv-x86_64-unknown-linux-gnu.tar.gz`, `uv-aarch64-unknown-linux-gnu.tar.gz`, etc.

**Manual:**
```yaml
architectures:
  amd64:
    release_pattern: "uv-x86_64-unknown-linux-musl.tar.gz"  # Specific variant
```

## Security

### Checksum Verification

The action automatically verifies SHA256 checksums for downloaded releases to ensure integrity and security:

**How it works:**
1. **Auto-discovers checksum files** from GitHub release assets
2. **Supports common formats**: `*.sha256`, `*.sha256sum`, `SHA256SUMS`, `checksums.txt`
3. **Verifies before extraction**: Prevents building from corrupted or tampered files
4. **Fails on mismatch**: Build stops if checksum doesn't match
5. **Graceful fallback**: Continues if no checksum file is available (with info message)

**Example output:**
```
ℹ️  Found checksum file: SHA256SUMS
ℹ️  Verifying checksum...
✅ Checksum verified: uv-x86_64-unknown-linux-gnu.tar.gz
```

**Failure behavior:**
```
❌ ERROR: Checksum verification failed for uv-x86_64-unknown-linux-gnu.tar.gz

Expected: abc123...
Actual:   def456...

The downloaded file may be corrupted or tampered with.
```

This feature provides automatic supply chain security without any configuration required.

## Configuration Reference

### Configuration File Structure

```yaml
# Package identification
package_name: string           # Name of the Debian package
github_repo: string            # GitHub repo in format "owner/repo"
artifact_format: string        # Archive format: "tar.gz", "tgz", or "zip"

# Debian distributions to target
debian_distributions:
  - bookworm
  - trixie
  - forky
  - sid

# Architecture Configuration (choose one format)

# Format 1: Auto-discovery (simple list)
architectures:
  - amd64
  - arm64
  - armhf

# Format 2: Manual patterns (object with release_pattern)
architectures:
  <debian-arch>:
    release_pattern: string    # Pattern with {version} placeholder

# Optional: Distribution-specific architecture support
distribution_arch_overrides:
  <arch>:
    distributions:
      - list of distributions supporting this arch

# Optional: Parallel build configuration
parallel_builds: boolean       # Default: true (enabled)
max_parallel: number           # Default: 2 (concurrent builds)

# Optional: Path to binary within extracted archive
binary_path: string            # Default: "" (binaries in root)
```

### Architecture Naming

Map Debian architecture names to upstream release artifact patterns:

| Debian Arch | Common Upstream Names | Notes |
|-------------|----------------------|-------|
| amd64       | x86_64, amd64 | All distributions |
| arm64       | aarch64, arm64 | All distributions |
| armel       | arm, armeabi | Bookworm and Trixie only (last release) |
| armhf       | armv7, armhf, arm-gnueabihf | All distributions |
| i386        | i386, i686, x86 | Bookworm only |
| ppc64el     | powerpc64le, ppc64le | All distributions |
| s390x       | s390x | All distributions |
| riscv64     | riscv64, riscv64gc | Trixie+ only |

## Examples

See the `examples/` directory for complete configuration examples:

- `examples/lazygit-config.yaml` - Simple CLI tool
- `examples/eza-config.yaml` - Rust-based tool with musl builds
- `examples/uv-config.yaml` - Full multi-arch with distribution overrides (riscv64 for Trixie+)
- `examples/distribution-specific-arch-config.yaml` - Distribution-specific architectures (i386 for Bookworm, armel for Bookworm+Trixie)

## Action Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `config-file` | Path to multiarch config YAML | Yes | - |
| `version` | Version of software to build | Yes | - |
| `build-version` | Debian build version number | Yes | - |
| `architecture` | Architecture to build or "all" | No | `all` |

## Action Outputs

| Output | Description |
|--------|-------------|
| `packages` | Space-separated list of generated .deb files |

## Build Summary

The action automatically generates a `build-summary.json` file containing comprehensive build metadata for easy integration with CI/CD pipelines and automation tools.

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
  "build_duration_seconds": 420,
  "build_start": "2025-10-17T10:30:00+0530",
  "build_end": "2025-10-17T10:37:00+0530",
  "parallel_builds": true,
  "max_parallel": 2,
  "packages": [
    {"name": "uv_0.9.3-1+bookworm_amd64.deb", "size": 12845632},
    {"name": "uv_0.9.3-1+bookworm_arm64.deb", "size": 11932456}
  ]
}
```

**Use cases:**
- **Automated artifact upload** - Parse package list for upload to apt repositories
- **Release notes generation** - Extract version and package details
- **Build monitoring** - Track build duration and success rates
- **CI/CD integration** - Use in GitHub Actions workflows for downstream jobs

**Example GitHub Actions integration:**
```yaml
- name: Build packages
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: 'multiarch-config.yaml'
    version: ${{ inputs.version }}
    build-version: ${{ inputs.build_version }}

- name: Parse build summary
  run: |
    PACKAGE_COUNT=$(jq '.total_packages' build-summary.json)
    BUILD_TIME=$(jq '.build_duration_seconds' build-summary.json)
    echo "Built $PACKAGE_COUNT packages in $BUILD_TIME seconds"
```

## Project Structure

The action code is organized into modular components for maintainability:

```
src/
├── lib/
│   ├── utils.sh          # Logging and output formatting
│   ├── config.sh         # Configuration parsing and validation
│   ├── github-api.sh     # GitHub API interactions
│   ├── discovery.sh      # Architecture pattern discovery
│   ├── validation.sh     # Release and checksum validation
│   ├── build.sh          # Core build functions
│   ├── orchestration.sh  # Build orchestration (parallel and sequential)
│   └── summary.sh        # Build summary generation
├── main.sh               # Main entry point
└── Dockerfile            # Docker build template
build.sh                  # Wrapper for backward compatibility
```

Each module has a focused responsibility, making the codebase easier to understand, test, and extend.

## Documentation

- **[Migration Guide](docs/MIGRATION.md)** - Migrating from single-arch to multi-arch builds
- **[Usage Guide](docs/USAGE.md)** - Detailed usage instructions and examples
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Reporting issues
- Submitting changes
- Development workflow
- Testing requirements

## License

MIT License - See LICENSE file for details

## Credits

Created by [@ranjithrajv](https://github.com/ranjithrajv)

Based on the multi-architecture work in [uv-debian](https://github.com/dariogriffo/uv-debian)

For use with packages hosted at [debian.griffo.io](https://debian.griffo.io) by [@dariogriffo](https://github.com/dariogriffo)

## Support

- Report issues: [GitHub Issues](https://github.com/ranjithrajv/debian-multiarch-builder/issues)
- Discussions: [GitHub Discussions](https://github.com/ranjithrajv/debian-multiarch-builder/discussions)
- Documentation: Check [docs/](docs/) directory for detailed guides
- Changelog: See [CHANGELOG.md](CHANGELOG.md) for release history
