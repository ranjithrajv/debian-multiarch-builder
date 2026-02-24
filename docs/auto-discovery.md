# Auto-Discovery Mode

Build Debian packages without creating any configuration files. Auto-discovery mode auto-detects everything from the GitHub repository.

## Quick Start

```bash
./build.sh --ad owner/repo version build-version
./build.sh --auto-discovery owner/repo version build-version
```

**Example:**
```bash
./build.sh --ad eza-community/eza v0.23.4 1
```

## How It Works

Auto-discovery mode performs the following steps automatically:

1. **Fetch Release Assets** - Queries GitHub API for release assets
2. **Detect Pattern** - Analyzes asset names to determine naming pattern
3. **Map Architectures** - Identifies which architectures are available
4. **Generate Config** - Creates temporary configuration
5. **Display Results** - Shows generated config and next steps

## Supported Patterns

Zero-config detects common release naming patterns:

### Pattern 1: Version in Filename
```
eza_v0.18.0_x86_64-unknown-linux-gnu.tar.gz
bat-v0.24.0-x86_64-unknown-linux-gnu.tar.gz
```

### Pattern 2: Version in Release Tag Only
```
eza_x86_64-unknown-linux-gnu.tar.gz  (version from release tag)
```

### Detected Architectures

| Release Asset Pattern | Detected Arch |
|----------------------|---------------|
| `x86_64`, `amd64` | amd64 |
| `aarch64`, `arm64` | arm64 |
| `armv7`, `armhf`, `armv7l` | armhf |
| `i686`, `i386` | i386 |

## Usage Examples

### Build Latest Version

```bash
# Get latest version from GitHub
latest=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | jq -r .tag_name)

# Build with auto-discovery
./build.sh --ad eza-community/eza $latest 1
```

### Build Specific Version

```bash
./build.sh --ad sharkdp/bat v0.24.0 1
./build.sh --ad BurntSushi/ripgrep 14.1.0 1
```

### Build for Single Architecture

```bash
./build.sh --ad eza-community/eza v0.23.4 1 amd64
```

## When Auto-Discovery Works Best

Auto-discovery works best for projects that:

✅ Publish pre-built Linux binaries
✅ Use standard naming patterns (arch in filename)
✅ Have consistent naming across architectures
✅ Publish releases on GitHub

## When to Use Manual Configuration

Use manual configuration when:

❌ Project doesn't publish pre-built binaries
❌ Non-standard naming patterns
❌ Need custom dependencies
❌ Need custom build scripts
❌ Need distribution-specific overrides

## Generated Configuration

Auto-discovery generates a configuration like this:

```yaml
# Auto-generated configuration for eza-community/eza
package_name: "eza"
github_repo: "eza-community/eza"
summary: "A modern alternative to ls"
license: "EUPL-1.2"

# Auto-detected download pattern
download_pattern: "eza_{arch}-unknown-linux-gnu.tar.gz"

# Auto-detected architecture mapping
architecture_map:
  amd64: "x86_64"
  arm64: "aarch64"
```

## Next Steps

After auto-discovery generates the configuration:

### Option 1: Build Immediately
```bash
./build.sh /tmp/autodiscover_owner_repo.yaml version 1
```

### Option 2: Save to Repository
```bash
cp /tmp/autodiscover_owner_repo.yaml .github/build-config.yaml
git add .github/build-config.yaml
git commit -m "Add build configuration"
```

### Option 3: Customize
```bash
cp /tmp/autodiscover_owner_repo.yaml .github/build-config.yaml
# Edit to add dependencies, adjust patterns, etc.
```

## Troubleshooting

### "Failed to auto-detect configuration"

**Causes:**
- Project doesn't publish pre-built Linux binaries
- Non-standard naming pattern
- Release doesn't exist

**Solutions:**
1. Check if releases exist: https://github.com/owner/repo/releases
2. Verify Linux binaries are published
3. Use manual configuration with templates

### "No release assets found"

**Causes:**
- Version doesn't exist
- Release has no assets yet

**Solutions:**
1. Check version number (try with/without 'v' prefix)
2. Use `--dry-run` to validate first

### Wrong Architecture Detected

**Solution:** Use manual configuration:
```bash
cp templates/rust/generic.yaml .github/build-config.yaml
# Edit architecture_map as needed
```

## Limitations

- Only works with GitHub-hosted releases
- Requires standard Linux binary naming
- Doesn't detect dependencies
- Doesn't create custom build scripts

## See Also

- [Setup Wizard](setup-wizard.md) - Interactive configuration generator
- [Templates](../templates/README.md) - Pre-built configurations
- [Dry-Run Validation](usage-guide.md#dry-run) - Validate before building
