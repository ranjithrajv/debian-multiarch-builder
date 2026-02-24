# Debian Multi-Architecture Package Builder

A reusable GitHub Action for building Debian packages across multiple architectures from upstream releases. This action simplifies the process of creating multi-architecture Debian packages for projects distributed via GitHub releases.

## 🚀 Quick Start (5-Minute Guide)

Get started in minutes by following these steps. This example shows how to build the [`eza`](https://github.com/eza-community/eza) package.

### Option 1: Auto-Discovery Mode (Fastest - No Configuration Required!)

Build directly from a GitHub repository without creating any configuration files:

```bash
./build.sh --ad eza-community/eza v0.23.4 1
```

Or in a GitHub Actions workflow:

```yaml
- name: Build with Auto-Discovery
  run: |
    git clone https://github.com/ranjithrajv/debian-multiarch-builder.git /tmp/builder
    /tmp/builder/build.sh --ad eza-community/eza v0.23.4 1
```

### Option 2: Interactive Setup Wizard

Let the wizard generate a configuration for you:

```bash
./build.sh --setup
```

The wizard will:
1. Detect your GitHub repository
2. Fetch the latest release version
3. Auto-detect download patterns
4. Generate a configuration file

### Option 3: Use a Template

Copy a pre-built template for popular projects:

```bash
cp templates/rust/eza.yaml .github/build-config.yaml
```

Available templates:
- **Rust:** eza, bat, ripgrep, generic
- **Go:** hugo, kubectl, generic
- **C/C++:** neovim, generic
- **Node.js, Python, Ruby:** generic templates

### Option 4: Manual Configuration

Create a configuration file manually:

**`.github/build-config.yaml`**
```yaml
package_name: "eza"
github_repo: "eza-community/eza"
summary: "A modern replacement for ls"
license: "MIT"

download_pattern: "eza_v{version}_{arch}-unknown-linux-gnu.tar.gz"

architecture_map:
  amd64: "x86_64"
  arm64: "aarch64"
  armhf: "armv7"
```

### Create a GitHub Actions Workflow

**`.github/workflows/build.yml`**

```yaml
name: Build Debian Package

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to build'
        required: true
        default: 'v0.23.4'

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

      - uses: actions/upload-artifact@v4
        with:
          name: debian-packages
          path: "*.deb"
```

### Run the Workflow

Go to the **Actions** tab in your GitHub repository, select the workflow, and click **Run workflow**.

---

## Why Use This Action?

*   **🚀 Auto-Discovery Mode** - Build from any GitHub repo without configuration
*   **🧙 Setup Wizard** - Interactive wizard generates config automatically  
*   **⚡ 80% Faster Builds** - Multi-level parallelization and intelligent caching
*   **🔒 Secure by Default** - Automatic checksum verification for all downloads
*   **✅ Quality Assurance** - Built-in Lintian integration for package validation
*   **📊 Real-time Progress** - Live build status with architecture-level tracking
*   **📦 12+ Templates** - Pre-built configs for popular Rust, Go, and C/C++ projects
*   **🤖 Auto-Discovery** - Automatically detects release patterns from GitHub

## Supported Debian Versions and Architectures

This action supports multiple Debian distributions and architectures. The table below shows the currently supported combinations:

| Debian Version | Codename | Status | Supported Architectures |
|----------------|----------|--------|-------------------------|
| 12 | bookworm | oldstable | amd64, arm64, armel, armhf, i386, mips64el, mipsel, ppc64el, s390x |
| 13 | trixie | stable | amd64, arm64, armel, armhf, i386, ppc64el, s390x, riscv64 |
| 14 | forky | testing | amd64, arm64, armhf, ppc64el, s390x, riscv64, loong64 |
| unstable | sid | perpetual | amd64, arm64, armhf, ppc64el, s390x, riscv64, loong64 |

**Architecture Notes:**
- `i386`: Full support in bookworm, reduced (partial userland) support in trixie and later
- `armel`: Full support in bookworm, limited security support in trixie and later
- `mipsel`, `mips64el`: Supported but deprecated in bookworm and trixie (limited porter support)
- `riscv64`: Introduced in Debian 13 (trixie), not available in bookworm
- `loong64`: Introduced in Debian 14 (forky), not available in bookworm or trixie
- Universal architectures (all distributions): `amd64`, `arm64`, `armhf`, `ppc64el`, `s390x`, `riscv64`, `loong64`
- `loong64` is the Debian architecture name for LoongArch processors

## Documentation

### Getting Started
- **[Quick Start Guide](docs/quick-start-guide.md)** - How to get started
- **[Usage Guide](docs/usage-guide.md)** - Detailed usage instructions and examples
- **[Core Concepts](docs/core-concepts.md)** - Core concepts of the action

### Features
- **[Auto-Discovery Mode](docs/auto-discovery.md)** - Build without configuration files
- **[Setup Wizard](docs/setup-wizard.md)** - Interactive configuration generator
- **[Templates](templates/README.md)** - Pre-built configurations for popular projects
- **[Auto-Discovery](docs/auto-discovery.md)** - How auto-discovery works

### Configuration
- **[Configuration Reference](docs/configuration-reference.md)** - Detailed configuration reference
- **[Best Practices](docs/best-practices.md)** - Best practices for using the action

### Performance
- **[Performance Tuning](docs/performance-tuning.md)** - Performance tuning and parallel builds
- **[Build Monitoring](docs/build-monitoring.md)** - Build output, progress tracking, and monitoring

### Quality & Security
- **[Security Guide](docs/security-guide.md)** - Checksum verification
- **[Lintian Integration](docs/lintian-integration.md)** - Package quality validation with lintian

### CI/CD Integration
- **[Build Summary](docs/build-summary.md)** - CI/CD integration guide
- **[Telemetry Guide](docs/telemetry-guide.md)** - Enhanced build metrics and monitoring

### Migration & Troubleshooting
- **[Migration Guide](docs/migration-guide.md)** - Migrating from single-arch to multi-arch builds
- **[Troubleshooting Guide](docs/troubleshooting-guide.md)** - Common issues and solutions

### Development
- **[Project Structure](docs/project-structure.md)** - Codebase organization
- **[Contributing](CONTRIBUTING.md)** - Contribution guidelines

## Action Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `config-file` | Path to multiarch config YAML | Yes | - |
| `version` | Version of software to build | Yes | - |
| `build-version` | Debian build version number | Yes | - |
| `architecture` | Architecture to build or "all" | No | `all` |
| `max-parallel` | Maximum concurrent builds (2-4 recommended) | No | `2` |
| `lintian-check` | Enable lintian validation of built packages | No | `false` |
| `telemetry-enabled` | Enable enhanced build telemetry and metrics collection | No | `true` |
| `save-baseline` | Save current build metrics as performance baseline | No | `false` |

For more details on the `max-parallel` setting, see the **[Configuration Reference](docs/configuration-reference.md#max-parallel-configuration)**.

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
