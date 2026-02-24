# GitHub Actions Workflows for debian-multiarch-builder

This directory contains ready-to-use GitHub Actions workflow templates for building Debian packages with debian-multiarch-builder.

## Quick Start

### Option 1: Demo Workflow (Recommended for First Time)

The demo workflow builds the `eza` package (a modern `ls` replacement).

**Steps:**
1. Copy `.github/workflows/demo.yml` to your repository
2. Copy `.github/demo-config.yaml` to your repository
3. Go to Actions tab → "Demo - Build Eza Package" → Run workflow
4. Download the `.deb` packages from workflow artifacts

### Option 2: Zero-Config Build

Build any GitHub project without creating a configuration file.

**Steps:**
1. Copy `.github/workflows/try-it.yml` to your repository
2. Run the workflow and enter the GitHub repo (e.g., `sharkdp/bat`)
3. Download the `.deb` packages from workflow artifacts

### Option 3: Setup Wizard

Generate a configuration file for your specific project.

**Steps:**
1. Copy `.github/workflows/setup.yml` to your repository
2. Run the workflow and enter your GitHub repo
3. Download the generated config from artifacts
4. Commit the config and use it in your build workflow

## Workflow Templates

### demo.yml
Builds the `eza` package as a demonstration. Best for:
- First-time users
- Testing the builder
- Understanding the workflow structure

### try-it.yml
Zero-config build for any GitHub project. Best for:
- Projects with standard release patterns
- Quick one-off builds
- Testing if a project is compatible

### setup.yml
Generates a configuration file. Best for:
- Projects with custom release patterns
- Setting up recurring builds
- Creating a permanent build workflow

## Customization

### Change the Package

Edit the workflow file and modify the inputs:

```yaml
inputs:
  version:
    default: 'v1.0.0'  # Change to your version
```

### Change the Config

For demo workflow, edit `.github/demo-config.yaml`:

```yaml
package_name: "your-package"
github_repo: "owner/your-repo"
download_pattern: "your-pattern_{version}_{arch}.tar.gz"
```

### Add More Architectures

Edit the `architecture_map` in your config:

```yaml
architecture_map:
  amd64: "x86_64"
  arm64: "aarch64"
  armhf: "armv7"
  i386: "i686"  # Add this line
```

### Enable Parallel Builds

Add to your config:

```yaml
parallel_builds: true
max_parallel: 2  # or higher for faster builds
```

## Build Outputs

After a successful build, you'll find:

1. **Debian Packages** (`.deb` files) - Uploaded as workflow artifacts
2. **Build Summary** (`build-summary.json`) - JSON with build details
3. **Build Logs** - Available in the workflow run output

## Retention

Workflow artifacts are retained for:
- Demo workflow: 30 days
- Try-it workflow: 7 days
- Setup workflow: 7 days

To download:
1. Go to Actions tab
2. Click on the workflow run
3. Scroll to "Artifacts" section
4. Click to download

## Troubleshooting

### Build Fails with "Version not found"
- Check the version format (try with/without 'v' prefix)
- Verify the release exists on GitHub

### Build Fails with "No release assets"
- The project may not publish pre-built binaries
- Check the release pattern in your config
- Try zero-config mode to auto-detect

### Build is Slow
- Enable parallel builds: `max_parallel: 2` or higher
- Use a larger runner: `runs-on: ubuntu-latest-8-cores`

## Need Help?

- Documentation: https://github.com/ranjithrajv/debian-multiarch-builder/tree/main/docs
- Issues: https://github.com/ranjithrajv/debian-multiarch-builder/issues
- Templates: https://github.com/ranjithrajv/debian-multiarch-builder/tree/main/templates
