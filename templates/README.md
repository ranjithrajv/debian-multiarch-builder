# Configuration Templates

Pre-built configuration templates for popular packages and project types. Copy the template that matches your project and customize it.

## Quick Start

```bash
# 1. Browse templates
ls templates/

# 2. Copy a template
cp templates/rust/eza.yaml .github/build-config.yaml

# 3. Customize (edit package_name, github_repo, download_pattern)

# 4. Build
./build.sh .github/build-config.yaml 0.18.0 1
```

## Templates by Language

### Rust Projects

| Template | Description | Use For |
|----------|-------------|---------|
| `rust/eza.yaml` | Eza (ls replacement) | Projects with `{arch}-unknown-linux-gnu` pattern |
| `rust/bat.yaml` | Bat (cat clone) | Projects with `-v{version}-{arch}` pattern |
| `rust/ripgrep.yaml` | Ripgrep (search) | Projects using musl static builds |
| `rust/generic.yaml` | Generic Rust | Starting point for any Rust project |

**Common Rust Patterns:**
```yaml
# GNU libc (most common)
download_pattern: "{name}_v{version}_{arch}-unknown-linux-gnu.tar.gz"
architecture_map:
  amd64: "x86_64"
  arm64: "aarch64"
  armhf: "armv7"

# Musl (static linking)
download_pattern: "{name}_v{version}_{arch}-unknown-linux-musl.tar.gz"
```

### Go Projects

| Template | Description | Use For |
|----------|-------------|---------|
| `go/hugo.yaml` | Hugo (static site) | Projects with consistent naming |
| `go/kubectl.yaml` | Kubectl (K8s CLI) | Projects with complex tarballs |
| `go/generic.yaml` | Generic Go | Starting point for any Go project |

**Common Go Patterns:**
```yaml
# GOOS_GOARCH format (most common)
download_pattern: "{name}_{version}_linux_{arch}.tar.gz"
architecture_map:
  amd64: "amd64"
  arm64: "arm64"

# GOOS-GOARCH format
download_pattern: "{name}_{version}_linux-{arch}.tar.gz"
```

### C/C++ Projects

| Template | Description | Use For |
|----------|-------------|---------|
| `c/neovim.yaml` | Neovim (editor) | Projects with subdirectory binaries |
| `c/generic.yaml` | Generic C/C++ | Starting point for C/C++ projects |

**Common C/C++ Patterns:**
```yaml
# Standard naming
download_pattern: "{name}-{version}-linux-{arch}.tar.gz"
architecture_map:
  amd64: "x86_64"
  arm64: "aarch64"
  armhf: "armhf"
```

### Node.js Projects

| Template | Description | Use For |
|----------|-------------|---------|
| `nodejs/generic.yaml` | Generic Node.js | Starting point for Node.js projects |

**Common Node.js Patterns:**
```yaml
download_pattern: "{name}-v{version}-linux-{arch}.tar.gz"
architecture_map:
  amd64: "x64"
  arm64: "arm64"
  armhf: "armv7l"
```

### Python Projects

| Template | Description | Use For |
|----------|-------------|---------|
| `python/generic.yaml` | Generic Python | Starting point for Python projects |

**Common Python Patterns:**
```yaml
download_pattern: "{name}-{version}-cp{python_version}-{arch}-linux-gnu.tar.gz"
```

## Template Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{version}` | Replaced with version number | `0.18.0` |
| `{arch}` | Replaced with architecture from map | `x86_64` |
| `{package_name}` | Replaced with package_name value | `eza` |

## Required Fields

```yaml
package_name: "my-app"      # Name of your package
github_repo: "owner/repo"   # GitHub repository
download_pattern: "..."     # Pattern to find release assets
```

## Optional Fields

```yaml
architecture_map:           # Map Debian arch to release arch names
  amd64: "x86_64"
  
binary_path: "bin/my-app"   # Path to binary inside archive

dependencies:               # Debian package dependencies
  - libc6
  - libssl3

artifact_format: "tar.gz"   # tar.gz, tgz, or zip (auto-detected if omitted)

parallel_builds: true       # Enable parallel builds
max_parallel: 2             # Maximum concurrent architecture builds
```

## Contributing Templates

Have a template for a popular project? Submit a PR!

1. Copy `templates/rust/generic.yaml`
2. Fill in the configuration for your project
3. Add entry to this README
4. Submit PR with description

## Need Help?

- Run `./build.sh config.yaml version 1 --dry-run` to validate your config
- See `docs/configuration-reference.md` for all options
- Open an issue for template requests
