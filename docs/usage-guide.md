# Usage Guide

This guide walks through integrating the Multi-Architecture Builder into an existing Debian package repository.

## Step-by-Step Integration

### For Existing Package Repositories (e.g., lazygit-debian)

#### Step 1: Add Configuration File

Create `multiarch-config.yaml` in your repository root:

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

**How to find release patterns:**
1. Go to your upstream GitHub releases page
2. Look at the asset names for a recent release
3. Replace the version number with `{version}`
4. Add entries for each architecture you want to support

#### Step 2: Update DEBIAN Control File

Edit `output/DEBIAN/control` to use placeholders:

**Before:**
```
Package: lazygit
Version: 2.35.0-1+bookworm
Architecture: amd64
```

**After:**
```
Package: PACKAGE_NAME
Version: VERSION-BUILD_VERSION+DIST
Architecture: SUPPORTED_ARCHITECTURES
```

#### Step 3: Update Changelog

Edit `output/changelog.Debian` to use placeholders:

**Before:**
```
lazygit (2.35.0-1+bookworm) bookworm; urgency=medium
```

**After:**
```
PACKAGE_NAME (FULL_VERSION) DIST; urgency=medium
```

#### Step 4: Update GitHub Workflow

Edit `.github/workflows/release.yml`:

**Before:**
```yaml
- name: Build lazygit
  run: ./build.sh ${{ inputs.version }} ${{ inputs.build_version }}
```

**After:**
```yaml
- name: Build multi-architecture packages
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: 'multiarch-config.yaml'
    version: ${{ inputs.version }}
    build-version: ${{ inputs.build_version }}
    architecture: ${{ inputs.architecture }}
    max-parallel: '2'  # Optional: control concurrent builds (default: 2)
```

Also add the architecture input to your workflow:

```yaml
on:
  workflow_dispatch:
    inputs:
      # ... existing inputs ...
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
```

#### Step 5: Remove Old Build Files (Optional)

You can now remove these files as they're provided by the action:
- `build.sh`
- `Dockerfile`

Or keep them for local testing.

#### Step 6: Test the Build

1. Commit your changes
2. Push to GitHub
3. Go to Actions > Your Workflow > Run workflow
4. Test with a single architecture first (e.g., amd64)
5. Once successful, try building all architectures

## Testing Locally

To test the configuration locally before pushing:

```bash
# Clone the action repo
git clone https://github.com/ranjithrajv/debian-multiarch-builder.git

# Copy build files to your package repo
cp debian-multiarch-builder/build.sh your-package-debian/
cp debian-multiarch-builder/Dockerfile your-package-debian/

# Run the build
cd your-package-debian
./build.sh multiarch-config.yaml <version> <build-version> amd64
```

## Troubleshooting

### Problem: Binary not found in extracted archive

**Solution:** Check if the binary is in a subdirectory. Add `binary_path` to your config:

```yaml
binary_path: "bin"  # if binaries are in a bin/ subdirectory
```

### Problem: Architecture not supported by upstream

**Solution:** Only add architectures that the upstream project actually releases. Check their GitHub releases page.

### Problem: Download fails

**Error:** `Failed to download release for arm64`

**Solution:** Verify the release pattern is correct:
1. Go to GitHub releases
2. Right-click on the asset and copy the link
3. Compare with your pattern
4. Make sure `{version}` placeholder matches the version format (with or without 'v' prefix)

### Problem: riscv64 fails on Bookworm

**Solution:** riscv64 is only supported on Trixie and later. Add distribution override:

```yaml
distribution_arch_overrides:
  riscv64:
    distributions:
      - trixie
      - forky
      - sid
```

## Adding New Architectures

When upstream adds support for a new architecture:

1. Check the release artifact name
2. Add to `multiarch-config.yaml`:
   ```yaml
   architectures:
     new-arch:
       release_pattern: "package_{version}_platform_new-arch.tar.gz"
   ```
3. Commit and push
4. Rebuild

The action will automatically build for the new architecture!

## Advanced Configuration

### Multiple Binaries

If your package includes multiple binaries:

```yaml
# The action copies all files from the extracted archive
# Just ensure your DEBIAN/control file lists them correctly
```

### Custom Archive Formats

Support for zip archives:

```yaml
artifact_format: zip
```

### Version Prefixes

If upstream uses 'v' prefix in version tags but not in filenames:

```yaml
# Workflow calls with version: "v1.2.3"
# But release pattern is:
release_pattern: "package_{version}_linux.tar.gz"
# Where {version} = "v1.2.3"

# Or if you need to strip the 'v':
# You may need to adjust in your workflow before calling the action
```

## Migration Checklist

- [ ] Create `multiarch-config.yaml`
- [ ] Update `output/DEBIAN/control` with placeholders
- [ ] Update `output/changelog.Debian` with placeholders
- [ ] Update `.github/workflows/release.yml`
- [ ] Add architecture input to workflow
- [ ] Test build with single architecture
- [ ] Test build with all architectures
- [ ] Update repository README
- [ ] (Optional) Remove old `build.sh` and `Dockerfile`

## Getting Help

- Check the main [README.md](README.md) for detailed documentation
- Look at [examples/](examples/) for reference configurations
- Open an issue on GitHub
- Check existing issues for similar problems
