# Configuration Reference

### Configuration File Structure

The action uses a 4-layer configuration system:

1. **`src/system.yaml`** - System constants (Debian policies, architecture patterns)
2. **`src/defaults.yaml`** - Action defaults (parallel builds, auto-discovery settings)
3. **`package.yaml`** - Your package definition (required)
4. **`overrides.yaml`** - Your custom overrides (optional)

#### package.yaml (Required)

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

# Optional: Path to binary within extracted archive
binary_path: string            # Default: "" (binaries in root)
```

#### overrides.yaml (Optional)

```yaml
# Optional: Distribution-specific architecture support
distribution_arch_overrides:
  <arch>:
    distributions:
      - list of distributions supporting this arch

# Optional: Parallel build configuration
parallel_builds:
  architectures:
    enabled: boolean           # Default: true
    max_concurrent: number     # Default: 2
  distributions:
    enabled: boolean           # Default: true

# Optional: Auto-discovery preferences
auto_discovery:
  exclude_patterns: [...]
  build_preferences: [...]

# Optional: Checksum verification patterns
checksum:
  file_patterns: [...]
  generic_patterns: [...]

# Optional: GitHub API endpoint (for GitHub Enterprise)
github_api_base_url: string    # Default: "https://api.github.com"
```

### Architecture Naming

Map Debian architecture names to upstream release artifact patterns:

| Debian Arch | Common Upstream Names | Notes |
|-------------|----------------------|-------|
| amd64       | x86_64, amd64 | All distributions |
| arm64       | aarch64, arm64 | All distributions |
| armel       | arm, armeabi | Bookworm only (auto-applied) |
| armhf       | armv7, armhf, arm-gnueabihf | All distributions |
| i386        | i386, i686, x86 | Bookworm only (auto-applied) |
| ppc64el     | powerpc64le, ppc64le | All distributions |
| s390x       | s390x | All distributions |
| riscv64     | riscv64, riscv64gc | Trixie+ only (auto-applied) |

### Built-in Distribution Rules

The action automatically applies Debian's official architecture support policies:

- **i386**: Bookworm only (deprecated in Trixie v13+)
- **armel**: Bookworm only (last version as regular architecture)
- **riscv64**: Trixie+ only (introduced in Trixie v13)

These rules are applied automatically—no configuration needed. You can override them with `distribution_arch_overrides` if your upstream has different support.
