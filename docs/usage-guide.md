# Usage Guide

Complete guide to using debian-multiarch-builder for building Debian packages across multiple architectures.

## Table of Contents

- [Quick Start](#quick-start)
- [Build Modes](#build-modes)
- [Command-Line Interface](#command-line-interface)
- [Configuration Files](#configuration-files)
- [Build Process](#build-process)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)

## Quick Start

### Option 1: Auto-Discovery Mode (Fastest)

Build directly from a GitHub repository without any configuration:

```bash
./build.sh --ad owner/repo version build-version
```

**Example:**
```bash
./build.sh --ad eza-community/eza v0.23.4 1
```

### Option 2: Setup Wizard

Let the wizard generate configuration for you:

```bash
./build.sh --setup
```

### Option 3: Use Template

Copy a pre-built template:

```bash
cp templates/rust/eza.yaml .github/build-config.yaml
./build.sh .github/build-config.yaml v0.23.4 1
```

### Option 4: Manual Configuration

Create your own configuration file and build:

```bash
./build.sh .github/build-config.yaml v0.23.4 1
```

## Build Modes

### Custom Configuration Mode

Standard build with configuration file:

```bash
./build.sh config.yaml version build-version [architecture]
```

**Arguments:**
- `config.yaml` - Path to configuration file
- `version` - Version to build (e.g., `v0.23.4`)
- `build-version` - Debian build version (e.g., `1`)
- `architecture` - Optional: specific architecture or `all` (default)

**Example:**
```bash
./build.sh .github/build-config.yaml v0.23.4 1 all
```

### Auto-Discovery Mode

Build without configuration file:

```bash
./build.sh --ad owner/repo version build-version [architecture]
./build.sh --auto-discovery owner/repo version build-version [architecture]
```

**Example:**
```bash
./build.sh --ad eza-community/eza v0.23.4 1
```

### Setup Wizard Mode

Interactive configuration generator:

```bash
./build.sh --setup
```

### Dry-Run Mode

Validate configuration without building:

```bash
./build.sh config.yaml version build-version --dry-run
```

**What it validates:**
1. Configuration file exists
2. YAML syntax is valid
3. Required fields are present
4. Version exists on GitHub
5. Release assets are available
6. Architecture availability
7. Estimated build time and cost

**Example output:**
```
==========================================
🔍 DRY RUN MODE - Validation Only
==========================================

📋 Step 1/5: Validating configuration file...
✅ Configuration file found: config.yaml

📋 Step 2/5: Parsing configuration...
✅ Package name: eza
✅ GitHub repo: eza-community/eza
✅ Download pattern: eza_v{version}_{arch}-unknown-linux-gnu.tar.gz
✅ YAML syntax: valid

📋 Step 3/5: Checking version availability...
✅ Version v0.23.4 exists

📋 Step 4/5: Checking release assets...
✅ Found 16 release assets
✅ amd64: Available
✅ arm64: Available
✅ armhf: Available

📋 Step 5/5: Estimating build resources...
ℹ️  Estimated build time: 4m 30s (parallel)
ℹ️  Estimated cost: $0.036 (GitHub Actions Ubuntu)

==========================================
✅ VALIDATION PASSED
==========================================
```

### Help Mode

Show help message:

```bash
./build.sh --help
./build.sh -h
```

## Command-Line Interface

### Synopsis

```bash
./build.sh <config-file> <version> <build-version> [architecture] [options]
./build.sh --setup
./build.sh --zero-config <repo> <version> <build-version> [architecture]
./build.sh --help
```

### Arguments

| Argument | Description | Required | Default |
|----------|-------------|----------|---------|
| `config-file` | Path to configuration YAML file | Yes* | - |
| `version` | Version to build | Yes* | - |
| `build-version` | Debian build version | Yes* | - |
| `architecture` | Target architecture or `all` | No | `all` |

*Not required when using `--setup` or `--auto-discovery`

### Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Validate configuration without building |
| `--help`, `-h` | Show help message |
| `--setup` | Run interactive setup wizard |
| `--auto-discovery`, `--ad` | Build without config file |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MAX_PARALLEL` | Maximum concurrent builds | `2` |
| `PARALLEL_BUILDS` | Enable parallel builds | `true` |
| `TELEMETRY_ENABLED` | Enable build telemetry | `true` |
| `LINTIAN_CHECK` | Enable lintian validation | `false` |
| `DEBUG` | Enable debug output | `false` |

**Example:**
```bash
MAX_PARALLEL=4 ./build.sh config.yaml v0.23.4 1
```

## Configuration Files

### Basic Configuration

Minimal configuration for most projects:

```yaml
package_name: "eza"
github_repo: "eza-community/eza"
download_pattern: "eza_v{version}_{arch}-unknown-linux-gnu.tar.gz"

architecture_map:
  amd64: "x86_64"
  arm64: "aarch64"
  armhf: "armv7"
```

### Complete Configuration

Full configuration with all options:

```yaml
# Package Information
package_name: "eza"
github_repo: "eza-community/eza"
summary: "A modern replacement for ls"
vendor: "Eza Community"
license: "MIT"

# Download Configuration
download_pattern: "eza_v{version}_{arch}-unknown-linux-gnu.tar.gz"
artifact_format: "tar.gz"  # tar.gz, tgz, or zip (auto-detected if omitted)

# Architecture Mapping
architecture_map:
  amd64: "x86_64"
  arm64: "aarch64"
  armhf: "armv7"
  i386: "i686"

# Build Settings
parallel_builds: true
max_parallel: 2

# Distributions (optional - uses all valid if omitted)
debian_distributions:
  - bookworm
  - trixie
  - forky
  - sid

# Dependencies (optional)
dependencies:
  - libc6
  - libgit2-1.7

# Distribution-specific overrides (optional)
distribution_arch_overrides:
  armhf:
    distributions: ["bookworm"]  # Only build armhf for bookworm
```

### Template Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{version}` | Replaced with version number | `v0.23.4` |
| `{arch}` | Replaced with architecture from map | `x86_64` |
| `{package_name}` | Replaced with package_name value | `eza` |

### Using Templates

Templates are pre-built configurations for popular projects:

```bash
# List available templates
ls templates/

# Copy a template
cp templates/rust/eza.yaml .github/build-config.yaml

# Customize if needed
nano .github/build-config.yaml

# Build
./build.sh .github/build-config.yaml v0.23.4 1
```

**Available Templates:**
- **Rust:** eza, bat, ripgrep, generic
- **Go:** hugo, kubectl, generic
- **C/C++:** neovim, generic
- **Node.js:** generic
- **Python:** generic
- **Ruby:** generic

## Build Process

### Step-by-Step Flow

1. **Configuration Parsing**
   - Load and validate YAML configuration
   - Apply defaults for missing values
   - Validate required fields

2. **Architecture Detection**
   - Fetch release assets from GitHub API
   - Match assets to configured architectures
   - Skip unavailable architectures

3. **Download**
   - Download release assets
   - Verify checksums (if available)
   - Cache downloads for reuse

4. **Extraction**
   - Extract archives (tar.gz, tgz, zip)
   - Locate binary in extracted files

5. **Package Building**
   - Create Debian package structure
   - Generate control files
   - Build .deb package with `dpkg-deb`

6. **Validation** (optional)
   - Run lintian checks
   - Report package quality issues

7. **Summary**
   - Generate build-summary.json
   - Display build statistics
   - Show viral badge

### Parallel Builds

By default, builds are parallelized:

- **Across architectures:** Multiple architectures build simultaneously
- **Across distributions:** Each distribution builds in parallel

**Control parallelism:**
```bash
# Limit concurrent builds
MAX_PARALLEL=2 ./build.sh config.yaml v0.23.4 1

# Disable parallel builds
PARALLEL_BUILDS=false ./build.sh config.yaml v0.23.4 1
```

### Build Output

**Progress indicators:**
```
🚀 Building eza version v0.23.4
📦 GitHub repo: eza-community/eza
🏗️  Architectures defined: 3

🔍 Detecting available architectures for eza version v0.23.4...
  ✓ amd64: Available
  ✓ arm64: Available
  ✓ armhf: Available

⚡ Parallel builds enabled (max: 2 concurrent)

🔨 Starting build for amd64 (1/3)...
🔨 Starting build for arm64 (2/3)...
✅ Completed build for amd64 (1m36s) [1/3]
🔨 Starting build for armhf (3/3)...
✅ Completed build for arm64 (1m24s) [2/3]
✅ Completed build for armhf (1m12s) [3/3]

==========================================
🎉 All attempted architectures built successfully!
==========================================

Generated packages:
  eza_0.23.4-1+bookworm_amd64.deb (2.1 MB)
  eza_0.23.4-1+bookworm_arm64.deb (2.0 MB)
  ...

📊 Build Summary:
  🔍 Detected: 3 architectures available
  🎯 Attempted: 12 packages (3 architectures × 4 distributions)
  ✅ Built: 12 packages
  📈 Success Rate: 100%
```

## Advanced Usage

### GitHub Actions Integration

**Basic workflow:**
```yaml
name: Build Debian Package

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to build'
        required: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Package
        uses: ranjithrajv/debian-multiarch-builder@v1
        with:
          config-file: .github/build-config.yaml
          version: ${{ github.event.inputs.version }}
          build-version: '1'
          max-parallel: 2

      - uses: actions/upload-artifact@v4
        with:
          name: debian-packages
          path: "*.deb"
```

**Zero-config workflow:**
```yaml
name: Auto-Discovery Build

on:
  workflow_dispatch:
    inputs:
      repo:
        description: 'GitHub repository'
        required: true
        default: 'eza-community/eza'
      version:
        description: 'Version to build'
        required: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build with Auto-Discovery
        run: |
          git clone https://github.com/ranjithrajv/debian-multiarch-builder.git /tmp/builder
          /tmp/builder/build.sh --ad ${{ github.event.inputs.repo }} ${{ github.event.inputs.version }} 1
      
      - uses: actions/upload-artifact@v4
        with:
          name: debian-packages
          path: "*.deb"
```

### Custom Build Scripts

Add custom pre/post build scripts in configuration:

```yaml
package_name: "myapp"
github_repo: "owner/myapp"

# Pre-build script
pre_build_script: |
  echo "Running pre-build tasks..."
  # Add custom tasks here

# Post-build script
post_build_script: |
  echo "Running post-build tasks..."
  # Sign packages, upload to repository, etc.
```

### Multi-Repo Builds

Build from multiple repositories in sequence:

```bash
# Build project A
./build.sh configs/project-a.yaml v1.0.0 1

# Build project B
./build.sh configs/project-b.yaml v2.0.0 1

# Build both with auto-discovery
./build.sh --ad owner/project-a v1.0.0 1
./build.sh --ad owner/project-b v2.0.0 1
```

### Automated Release Pipeline

Complete CI/CD pipeline:

```yaml
name: Auto-Build on Release

on:
  release:
    types: [published]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Package
        uses: ranjithrajv/debian-multiarch-builder@v1
        with:
          config-file: .github/build-config.yaml
          version: ${{ github.ref_name }}
          build-version: '1'
      
      - name: Upload to Release
        uses: softprops/action-gh-release@v1
        with:
          files: "*.deb"
```

## Troubleshooting

### Common Issues

#### Configuration File Not Found

**Error:** `Configuration file not found: config.yaml`

**Solutions:**
1. Check file path is correct
2. Create configuration: `./build.sh --setup`
3. Use template: `cp templates/rust/eza.yaml config.yaml`

#### Version Not Found

**Error:** `Version v1.0.0 not found for owner/repo`

**Solutions:**
1. Check version format (try without 'v' prefix)
2. Verify release exists: https://github.com/owner/repo/releases
3. Use dry-run to validate: `./build.sh config.yaml version 1 --dry-run`

#### No Release Assets

**Error:** `No release assets found for version`

**Solutions:**
1. Verify project publishes pre-built binaries
2. Check download_pattern matches asset names
3. Use auto-discovery to detect: `./build.sh --ad owner/repo version 1`

#### Architecture Not Available

**Warning:** `armhf: Not available`

**Solutions:**
1. Remove architecture from config if not needed
2. Check if upstream publishes this architecture
3. Use distribution_arch_overrides to limit

#### Build Failed

**Error:** `Build failed for architecture amd64`

**Solutions:**
1. Check build log: `build_amd64.log`
2. Verify dependencies are installed
3. Run with debug: `DEBUG=true ./build.sh config.yaml version 1`

### Debug Mode

Enable verbose output:

```bash
DEBUG=true ./build.sh config.yaml v0.23.4 1
```

### Build Logs

Logs are saved to:
- `build_amd64.log` - amd64 build log
- `build_arm64.log` - arm64 build log
- `build-summary.json` - Complete build summary

### Get Help

- **Documentation:** `docs/` directory
- **Issues:** https://github.com/ranjithrajv/debian-multiarch-builder/issues
- **Discussions:** https://github.com/ranjithrajv/debian-multiarch-builder/discussions

## See Also

- [Configuration Reference](configuration-reference.md) - All configuration options
- [Auto-Discovery Mode](auto-discovery.md) - Build without configuration
- [Setup Wizard](setup-wizard.md) - Interactive configuration generator
- [Templates](../templates/README.md) - Pre-built configurations
- [Troubleshooting Guide](troubleshooting-guide.md) - Common issues and solutions
