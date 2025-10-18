# Quick Start

This guide provides the steps to get started with the Debian Multi-Architecture Package Builder action.

### 1. Create Configuration Files

Create a `package.yaml` in your repository root:

**Option A: Minimal Configuration (Recommended)**

This is the simplest way to get started. The action will automatically build for all supported distributions and architectures.

```yaml
# package.yaml
package_name: lazygit
github_repo: jesseduffield/lazygit
artifact_format: tar.gz
```

**Option B: Auto-discovery**

This option allows you to specify the distributions and architectures you want to build for.

```yaml
# package.yaml
package_name: lazygit
github_repo: jesseduffield/lazygit
artifact_format: tar.gz

debian_distributions:
  - bookworm
  - trixie

architectures:
  - amd64
  - arm64
```

**Option C: Manual Patterns (Advanced)**

**Optional: Create `overrides.yaml` for customizations**
```yaml
# overrides.yaml (optional)
# Customize build settings without modifying package.yaml

parallel_builds:
  architectures:
    enabled: true
    max_concurrent: 4  # Use more CPUs on self-hosted runners

  distributions:
    enabled: true
```

## 2. Create or Update Workflow

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
          config-file: 'package.yaml'
          version: ${{ inputs.version }}
          build-version: ${{ inputs.build_version }}
          architecture: ${{ inputs.architecture }}
          max-parallel: '2'  # Optional: control concurrent builds (default: 2)

      - uses: actions/upload-artifact@v4
        with:
          name: debian-packages
          path: '*.deb'
```

## 3. Update DEBIAN/control File

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

## 4. Update changelog.Debian

Your `output/changelog.Debian` should use placeholders:

```
PACKAGE_NAME (FULL_VERSION) DIST; urgency=medium

  * New upstream release

 -- Your Name <your.email@example.com>  Mon, 01 Jan 2024 00:00:00 +0000
```
