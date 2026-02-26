# Troubleshooting Guide

This guide provides solutions to common issues you may encounter when using the Debian Multi-Architecture Package Builder.

## Common Errors

### "Release not found"

This error occurs when the action is unable to find the specified release artifact. Here are some common causes and solutions:

*   **Incorrect version:** Make sure that the `version` you specified in your workflow exists as a release tag in the upstream repository.
*   **Incorrect release pattern:** If you are not using auto-discovery, make sure that the `release_pattern` in your `package.yaml` file is correct. You can check the release assets on the GitHub releases page to find the correct pattern.
*   **Architecture not published:** The upstream project may not publish release artifacts for the architecture you are trying to build for.

### "Checksum verification failed"

This error occurs when the checksum of the downloaded release artifact does not match the expected checksum. This could be due to a corrupted download or a tampered file. You can try re-running the workflow to see if the error persists. If it does, you should contact the maintainer of the upstream project to report the issue.

### "Binary source not found"

This error occurs when the action is unable to find the binary in the extracted release artifact. This is usually because the binary is not in the root of the archive. You can use the `binary_path` option in your `package.yaml` file to specify the path to the binary within the archive.

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

There are two common causes:

**1. Flat archive (no subdirectory)**

Some upstreams publish archives that extract a single binary directly to the current directory with no top-level subdirectory (e.g., `./eza` rather than `./eza-v1.0.0/eza`). The action handles this automatically by inspecting the archive before extracting. If you see this error on a flat archive, verify that the `release_pattern` is correct and the archive is downloading successfully.

```bash
# Check archive structure before extraction
curl -sL https://github.com/owner/repo/releases/download/v1.0.0/file.tar.gz \
  | tar -tzf - | head -20
# Flat: shows   ./binary_name
# Dir:  shows   binary_name-v1.0.0/
#               binary_name-v1.0.0/bin/
```

**2. Binary in a subdirectory**

If the archive extracts a directory with binaries nested inside, use `binary_path`:

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

### Release pattern `{version}` placeholder

**Note:** `{version}` in `release_pattern` is **optional**. Many upstream projects do not include the version number in release asset filenames (e.g., eza publishes `eza_x86_64-unknown-linux-gnu.tar.gz` across all releases). Only add `{version}` if the upstream asset filename actually contains the version string.

**When to use `{version}`:**
```yaml
# ✓ Use when the asset filename contains the version, e.g.:
# app-1.2.3-x86_64.tar.gz
release_pattern: "app-{version}-x86_64.tar.gz"

# ✗ Do NOT use when the asset filename has no version, e.g.:
# app_x86_64-unknown-linux-gnu.tar.gz
release_pattern: "app_x86_64-unknown-linux-gnu.tar.gz"
```

**Bash expansion pitfall:** The `{version}` substitution uses bash string replacement. If `{version}` appears inside `${...}`, the inner `}` prematurely closes the outer expansion and corrupts the pattern. The action handles this internally — but if you are forking or extending the action, use an intermediate variable:
```bash
# Correct way to substitute {version} in bash:
local _ver='{version}'
pattern="${pattern//$_ver/$VERSION}"
```

## Parallel Build Failures

### Builds complete in ~5 seconds with no packages generated

**Problem:** Parallel architecture builds exit silently with no error output; the final summary shows "no packages were generated."

**Cause:** When `error()` calls `exit 1` deep inside a background subshell, it bypasses the code that writes the FAILED status file. The orchestration loop cannot detect the failure, logs are cleaned up, and the build appears to succeed vacuously.

**Diagnosis:** Check if a status file was written for the failed architecture:
```bash
# During a run (from another terminal)
ls build_*.status
cat build_amd64.status  # Should say SUCCESS or FAILED
```

**If status files are missing:** This is a known race condition that was fixed in v0.2.1. Ensure you are on an up-to-date version of the action.

**Workaround for debugging:** Run sequentially to see the error output directly:
```yaml
# In your config or workflow input
parallel_builds: false
```

Or reduce to a single architecture:
```yaml
architecture: amd64
```

### Failed architecture build log is empty or missing

**Problem:** `build_amd64.log` is empty or the log is cleaned up before you can read it.

**Solution:** The action now prints the first 30 lines of failed build logs to stdout before cleanup. Check the workflow run log output for lines beginning with `Error log for <arch>:`.

For detailed logs, set `parallel_builds: false` to run sequentially — output goes directly to stdout.

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
