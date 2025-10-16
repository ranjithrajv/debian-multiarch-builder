# Debian Multi-Architecture Package Builder

A reusable GitHub Action for building Debian packages across multiple architectures from upstream releases. This action simplifies the process of creating multi-architecture Debian packages for projects distributed via GitHub releases.

## Features

- Build Debian packages for multiple architectures: amd64, arm64, armel, armhf, ppc64el, s390x, riscv64
- Support for multiple Debian distributions: Bookworm, Trixie, Forky, Sid
- Configuration-driven approach using YAML
- Automatic download and extraction of upstream releases
- Distribution-specific architecture support (e.g., riscv64 only on newer distributions)
- Docker-based builds for reproducibility
- Single command to build all architectures or specific ones

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

```yaml
package_name: lazygit
github_repo: jesseduffield/lazygit
artifact_format: tar.gz

debian_distributions:
  - bookworm
  - trixie
  - forky
  - sid

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

# Architecture mappings
architectures:
  <debian-arch>:
    release_pattern: string    # Pattern with {version} placeholder

# Optional: Distribution-specific architecture support
distribution_arch_overrides:
  <arch>:
    distributions:
      - list of distributions supporting this arch

# Optional: Path to binary within extracted archive
binary_path: string            # Default: "" (binaries in root)
```

### Architecture Naming

Map Debian architecture names to upstream release artifact patterns:

| Debian Arch | Common Upstream Names |
|-------------|----------------------|
| amd64       | x86_64, amd64 |
| arm64       | aarch64, arm64 |
| armel       | arm, armeabi |
| armhf       | armv7, armhf, arm-gnueabihf |
| ppc64el     | powerpc64le, ppc64le |
| s390x       | s390x |
| riscv64     | riscv64, riscv64gc |

## Examples

See the `examples/` directory for complete configuration examples:

- `examples/lazygit-config.yaml` - Simple CLI tool
- `examples/eza-config.yaml` - Rust-based tool with musl builds
- `examples/uv-config.yaml` - Full multi-arch with distribution overrides

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

## Migration Guide

### From Single-Arch Build

If you have an existing single-architecture build setup:

1. **Create config file** - Add `multiarch-config.yaml` with your current architecture
2. **Update workflow** - Replace custom build step with this action
3. **Add more architectures** - Add additional architecture mappings as needed
4. **Update control files** - Replace hardcoded values with placeholders

### Minimal Changes Required

For each package repository, you only need to:
1. Add `multiarch-config.yaml` (new file)
2. Update `.github/workflows/release.yml` (modify existing)
3. Update `output/DEBIAN/control` (add placeholders)

Your `Dockerfile` and `build.sh` can be removed - the action provides these.

## Advantages

- **Centralized Maintenance**: Update build logic in one place, benefits all packages
- **Consistency**: All packages use the same build process
- **Easy Updates**: Add new architectures globally without touching individual repos
- **Reduced Duplication**: No need to copy/paste build scripts across repos
- **Version Control**: Pin action to specific version for stability
- **Testing**: Test changes in action repo before deploying to production

## Contributing

Contributions welcome! Please:
1. Fork this repository
2. Create a feature branch
3. Test with example configurations
4. Submit a pull request

## License

MIT License - See LICENSE file for details

## Credits

Created by [@ranjithrajv](https://github.com/ranjithrajv)

Based on the multi-architecture work in [uv-debian](https://github.com/dariogriffo/uv-debian)

For use with packages hosted at [debian.griffo.io](https://debian.griffo.io) by [@dariogriffo](https://github.com/dariogriffo)

## Support

- Report issues: [GitHub Issues](https://github.com/ranjithrajv/debian-multiarch-builder/issues)
- Discussions: [GitHub Discussions](https://github.com/ranjithrajv/debian-multiarch-builder/discussions)
