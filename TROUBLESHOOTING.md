# Troubleshooting Guide

Common issues and solutions when using debian-multiarch-builder.

## Configuration Errors

### Error: "Configuration file not found"

**Problem:** The config file path is incorrect or file doesn't exist.

**Solution:**
```bash
# Check if file exists
ls -la multiarch-config.yaml

# Use absolute path if needed
uses: ranjithrajv/debian-multiarch-builder@v1
with:
  config-file: '/full/path/to/multiarch-config.yaml'
```

### Error: "Invalid YAML syntax"

**Problem:** Your multiarch-config.yaml has syntax errors.

**Solution:**
```bash
# Validate YAML locally
yq eval '.' multiarch-config.yaml

# Common issues:
# - Inconsistent indentation (use spaces, not tabs)
# - Missing colons after keys
# - Incorrect list syntax
```

**Example of correct YAML:**
```yaml
package_name: myapp
architectures:
  amd64:                         # Note the colon
    release_pattern: "file.tgz"  # Proper indentation
```

### Error: "Missing required field 'package_name'"

**Problem:** Required configuration field is missing.

**Solution:**
Ensure your config has all required fields:
```yaml
package_name: your-package    # Required
github_repo: owner/repo       # Required
debian_distributions:         # Required
  - bookworm
architectures:                # Required
  amd64:
    release_pattern: "..."    # Required for each arch
```

### Error: "Invalid github_repo format"

**Problem:** GitHub repo is not in `owner/repo` format.

**Wrong:**
```yaml
github_repo: https://github.com/owner/repo
github_repo: github.com/owner/repo
github_repo: owner-repo
```

**Correct:**
```yaml
github_repo: owner/repo
```

## Download Errors

### Error: "Release not found"

**Problem:** The upstream release doesn't exist or release pattern is wrong.

**Solution:**
1. Visit the GitHub releases page shown in the error
2. Check if the version exists
3. Compare release asset names with your `release_pattern`
4. Ensure `{version}` placeholder matches actual version format

**Example:**
```bash
# If error shows:
# https://github.com/owner/repo/releases/download/v1.0.0/app-x86_64.tar.gz

# Your version input might need 'v' prefix:
version: v1.0.0  # Not just 1.0.0

# Or your pattern needs adjustment:
release_pattern: "app-{version}-x86_64.tar.gz"  # If version is in filename
```

### Error: "Failed to download release"

**Problem:** Network issues or authentication required.

**Solution:**
- Check your internet connection
- Verify the release is public (not draft or private)
- Some repos require GitHub authentication

## Extraction Errors

### Error: "Binary source not found"

**Problem:** The extracted archive structure doesn't match expectations.

**Solution:**

1. Check the error message for directory listing
2. Add `binary_path` to your config if binaries are in a subdirectory:

```yaml
# If binaries are in bin/ subdirectory after extraction
binary_path: "bin"

# If binaries are in app-name/bin/
binary_path: "app-name/bin"
```

**To debug locally:**
```bash
# Download and extract manually
wget https://github.com/owner/repo/releases/download/v1.0.0/file.tar.gz
tar -xzf file.tar.gz
ls -la  # Check structure
```

### Error: "Failed to extract archive"

**Problem:** Archive is corrupted or format mismatch.

**Solution:**
- Verify `artifact_format` in config matches actual file type
- Try downloading manually to verify file integrity
- Supported formats: `tar.gz`, `tgz`, `zip`

## Build Errors

### Error: "Failed to build Docker image"

**Problem:** Dockerfile or control file has issues.

**Common causes:**
1. Missing required directories in `output/`
2. Invalid placeholders in control file
3. Docker daemon not running

**Solution:**
```bash
# Check required directories exist
ls -la output/DEBIAN/
ls -la output/DEBIAN/control

# Test Docker
docker ps

# Check control file has correct placeholders
cat output/DEBIAN/control
# Should contain: PACKAGE_NAME, VERSION, ARCH, etc.
```

### Error: "Architecture not found in config"

**Problem:** Requested architecture doesn't exist in your config.

**Solution:**
```bash
# Check which architectures are defined
yq eval '.architectures | keys' multiarch-config.yaml

# Add missing architecture:
architectures:
  arm64:  # Add this
    release_pattern: "app-{version}-aarch64.tar.gz"
```

## Tool Errors

### Error: "yq is not installed"

**Problem:** yq YAML processor is missing.

**Solution:**
```bash
# Install yq
# On Ubuntu/Debian:
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Or via package manager:
sudo snap install yq
```

### Error: "Docker is not installed"

**Problem:** Docker is not available.

**Solution:**
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Add user to docker group
sudo usermod -aG docker $USER

# Restart session or run:
newgrp docker
```

### Error: "Docker daemon is not running"

**Problem:** Docker service is stopped.

**Solution:**
```bash
# Start Docker
sudo systemctl start docker

# Enable on boot
sudo systemctl enable docker
```

## GitHub Actions Specific

### Error: "Permission denied" in GitHub Actions

**Problem:** Workflow doesn't have necessary permissions.

**Solution:**
Add to your workflow:
```yaml
permissions:
  contents: write  # For creating releases
```

### Error: "No such file or directory" for config

**Problem:** Config file path is relative to wrong directory.

**Solution:**
```yaml
steps:
  - uses: actions/checkout@v4  # Must checkout first!

  - uses: ranjithrajv/debian-multiarch-builder@v1
    with:
      config-file: 'multiarch-config.yaml'  # Relative to repo root
```

## Performance Issues

### Build is very slow

**Possible causes:**
1. Building all architectures sequentially
2. Large upstream releases
3. Many distributions

**Solutions:**
- Build single architecture for testing:
  ```yaml
  architecture: amd64  # Instead of 'all'
  ```
- Consider caching Docker layers
- Reduce number of distributions if not all are needed

## Validation Issues

### Warning: "Unknown distribution"

**Problem:** Using a non-standard Debian distribution name.

**Impact:** Just a warning, build will proceed.

**Standard distributions:** bookworm, trixie, forky, sid

**Solution:**
```yaml
# If you need custom distributions, warnings are safe to ignore
# But ensure the base Docker image supports it:
debian_distributions:
  - your-custom-dist  # Will show warning but continue
```

### Warning: "Release pattern doesn't contain {version} placeholder"

**Problem:** Pattern is missing `{version}` placeholder.

**Impact:** Version won't be substituted, downloads may fail.

**Solution:**
```yaml
# Wrong:
release_pattern: "app-1.0.0-amd64.tar.gz"

# Correct:
release_pattern: "app-{version}-amd64.tar.gz"
```

## Getting More Help

1. **Enable debug output:**
   ```bash
   # Run locally with set -x for debugging
   bash -x build.sh config.yaml 1.0.0 1 amd64
   ```

2. **Check examples:**
   - Look at working examples in `examples/` directory
   - Compare with uv-config.yaml (known working)

3. **Test locally first:**
   ```bash
   # Clone the action repo
   git clone https://github.com/ranjithrajv/debian-multiarch-builder.git

   # Copy files to your package repo
   cp debian-multiarch-builder/build.sh .
   cp debian-multiarch-builder/Dockerfile .

   # Test build
   ./build.sh multiarch-config.yaml 1.0.0 1 amd64
   ```

4. **Report issues:**
   - https://github.com/ranjithrajv/debian-multiarch-builder/issues
   - Include:
     - Your multiarch-config.yaml
     - Full error message
     - GitHub Actions workflow (if applicable)
