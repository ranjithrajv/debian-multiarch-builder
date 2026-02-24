# Setup Wizard

Interactive configuration generator that guides you through creating a build configuration.

## Quick Start

```bash
./build.sh --setup
```

## How It Works

The setup wizard asks you a series of questions:

1. **GitHub Repository** - Detects from git remote or asks
2. **Version** - Fetches latest release or asks
3. **Output Location** - Suggests `.github/build-config.yaml`
4. **Generation** - Auto-detects patterns and generates config

## Example Session

```
$ ./build.sh --setup

==========================================
🔧 Debian Multi-Arch Builder Setup Wizard
==========================================

This wizard will help you create a configuration file.
It will auto-detect settings from your GitHub repository.

Detected from git remote: eza-community/eza

📋 Step 1/3: GitHub Repository

Detected from git remote: eza-community/eza
Use this repository? [Y/n]: y

📋 Step 2/3: Version

Latest release: v0.23.4
Build this version? [Y/n]: y

📋 Step 3/3: Configuration File

Default output: .github/build-config.yaml
Use this location? [Y/n]: y

==========================================
Generating Configuration...
==========================================

🔍 Auto-discovering configuration for eza-community/eza...

ℹ️  INFO: Detected latest version: v0.23.4
ℹ️  INFO: Detected download pattern: eza_{arch}-unknown-linux-gnu.tar.gz
ℹ️  INFO: Detected architectures:
     amd64: "x86_64"
     arm64: "aarch64"

✅ Configuration generated: .github/build-config.yaml

Next steps:
  1. Review the generated configuration
  2. Customize if needed (add dependencies, adjust patterns)
  3. Run: ./build.sh .github/build-config.yaml v0.23.4 1
```

## Non-Interactive Mode

For CI/CD or scripted usage:

```bash
./build.sh --setup << EOF
y
owner/repo
y
v1.0.0
y
.github/build-config.yaml
y
EOF
```

## Generated Configuration

The wizard generates a configuration like:

```yaml
# Auto-generated configuration for owner/repo
# Generated on: 2026-02-24T23:11:19+05:30

package_name: "repo"
github_repo: "owner/repo"
summary: "Project description from GitHub"
license: "MIT"

download_pattern: "repo_{arch}-unknown-linux-gnu.tar.gz"

architecture_map:
  amd64: "x86_64"
  arm64: "aarch64"
```

## Customization

After generation, you can customize:

### Add Dependencies
```yaml
dependencies:
  - libc6
  - libssl3
  - libgit2-1.7
```

### Adjust Parallelism
```yaml
parallel_builds: true
max_parallel: 4
```

### Add Distribution Overrides
```yaml
distribution_arch_overrides:
  armhf:
    distributions: ["bookworm"]
```

## Use Cases

### First-Time Users
Perfect for users who have never used the tool before. The wizard handles all the complexity.

### New Projects
Quick way to generate initial configuration for a new project.

### Migration
When migrating from another build system, the wizard provides a starting point.

### Testing
Quickly generate configs for testing different projects.

## Troubleshooting

### Not in Git Repository

**Error:** "Not in a git repository. Auto-detection will be limited."

**Solution:** Enter repository manually when prompted.

### No Releases Found

**Error:** "Could not detect latest version"

**Solution:** Enter version manually when prompted.

### Pattern Detection Failed

**Error:** "Could not auto-detect download pattern"

**Solution:**
1. Check if project publishes Linux binaries
2. Use templates instead: `cp templates/rust/generic.yaml .github/build-config.yaml`
3. Create manual configuration

## Next Steps

After running the wizard:

1. **Review** the generated configuration
2. **Test** with dry-run: `./build.sh config.yaml version 1 --dry-run`
3. **Build**: `./build.sh config.yaml version 1`
4. **Commit** the configuration to your repo

## See Also

- [Auto-Discovery Mode](auto-discovery.md) - Build without configuration
- [Templates](../templates/README.md) - Pre-built configurations
- [Configuration Reference](configuration-reference.md) - All configuration options
