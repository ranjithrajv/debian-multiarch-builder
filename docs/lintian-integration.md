# Lintian Integration

The Debian Multi-Architecture Package Builder includes built-in support for [Lintian](https://lintian.debian.org/), the Debian package checker. Lintian performs static analysis on Debian packages to detect policy violations, common errors, and packaging issues.

## What is Lintian?

Lintian is the official Debian tool for checking packages against Debian Policy and common best practices. It can detect:

- **Policy Violations**: Non-compliance with Debian Policy Manual
- **Missing Dependencies**: Binaries that require libraries not listed in dependencies
- **Permission Issues**: Incorrect file permissions in packages
- **Missing Documentation**: Packages without manpages or documentation
- **Spelling Errors**: Common typos in package descriptions
- **And much more**: Over 200+ checks covering various aspects of package quality

## Enabling Lintian Checks

Lintian validation is **opt-in** and disabled by default. Enable it by setting the `lintian-check` input to `true`:

```yaml
- name: Build multi-architecture packages
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: 'package.yaml'
    version: '2.0.0'
    build-version: '1'
    lintian-check: 'true'  # Enable lintian validation
```

## Configuration

Lintian behavior can be customized in your `overrides.yaml` file:

```yaml
lintian:
  enabled: true              # Controlled by action input, don't change
  fail_on_errors: true       # Fail build if lintian reports errors
  fail_on_warnings: false    # Continue build even with warnings
  pedantic: false            # Enable pedantic checks
  display_level: "info"      # Minimum severity: info, warning, error
  suppress_tags:             # List of lintian tags to ignore
    - new-package-should-close-itp-bug
    - changelog-file-missing-in-native-package
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `fail_on_errors` | `true` | Stop build when lintian reports errors |
| `fail_on_warnings` | `false` | Stop build when lintian reports warnings |
| `pedantic` | `false` | Enable pedantic checks (more strict) |
| `display_level` | `info` | Show messages at or above this level |
| `suppress_tags` | `[]` | List of lintian tags to ignore |

### Display Levels

- **`info`**: Show all lintian output (errors, warnings, and info messages)
- **`warning`**: Show only warnings and errors
- **`error`**: Show only errors

## Output Format

### Real-time Output

During the build, lintian results are displayed for each package:

```
✅ Completed build for amd64 (45s) [1/3]
   ✅ Lintian: No issues found

✅ Completed build for arm64 (52s) [2/3]
   ⚠️  Lintian: 2 warning(s), 1 info
      W: mypackage: binary-without-manpage usr/bin/myapp
      W: mypackage: package-contains-no-arch-dependent-files

❌ Failed build for armhf (38s) [3/3]
   ❌ Lintian: 1 error(s), 0 warning(s), 0 info
      E: mypackage: missing-dependency libssl3
```

### Summary Report

At the end of the build, a summary is displayed:

```
==========================================
📋 Lintian Summary
==========================================
   Errors:   1
   Warnings: 4
   Info:     2

   Review the lintian output above for details.
   Common issues: missing dependencies, policy violations, permission errors

```

### JSON Report

Lintian results are included in `build-summary.json`:

```json
{
  "package": "myapp",
  "version": "2.0.0",
  "build_version": "1",
  "lintian": {
    "enabled": true,
    "total_errors": 1,
    "total_warnings": 4,
    "total_info": 2,
    "packages": [
      {
        "package": "myapp_2.0.0-1+bookworm_amd64",
        "errors": 0,
        "warnings": 1,
        "info": 0
      },
      {
        "package": "myapp_2.0.0-1+bookworm_arm64",
        "errors": 1,
        "warnings": 1,
        "info": 1
      }
    ]
  }
}
```

## Common Lintian Issues and Solutions

### Missing Dependencies

**Error:**
```
E: mypackage: missing-dependency libssl3
```

**Solution:** Add the missing library to your package's dependencies in `templates/output/DEBIAN/control`:
```
Depends: libssl3
```

### Binary Without Manpage

**Warning:**
```
W: mypackage: binary-without-manpage usr/bin/myapp
```

**Solutions:**
1. Add a manpage to your package
2. If a manpage doesn't make sense, suppress this tag:
```yaml
lintian:
  suppress_tags:
    - binary-without-manpage
```

### Permission Issues

**Error:**
```
E: mypackage: executable-not-elf-or-script usr/share/doc/myapp/README
```

**Solution:** Fix file permissions in your Dockerfile or build process to ensure only executable files have execute permission.

### Package Contains No Architecture-Dependent Files

**Warning:**
```
W: mypackage: package-contains-no-arch-dependent-files
```

**Solution:** This is common when packaging pre-built binaries. You can either:
1. Set the architecture to `all` if the package truly is architecture-independent
2. Suppress this tag if you're intentionally building for multiple architectures

## Suppressing Specific Tags

Some lintian tags may not apply to your use case. For example, when redistributing upstream binaries, you might want to suppress:

```yaml
lintian:
  suppress_tags:
    - new-package-should-close-itp-bug          # Only relevant for official Debian packages
    - changelog-file-missing-in-native-package  # May not apply to repackaged binaries
    - binary-without-manpage                    # If upstream doesn't provide manpages
    - package-contains-no-arch-dependent-files  # Common for repackaged binaries
```

## Best Practices

1. **Start with errors only**: First fix all errors, then address warnings
   ```yaml
   lintian:
     fail_on_errors: true
     fail_on_warnings: false
     display_level: "error"
   ```

2. **Enable for production builds**: Use lintian in your main build pipeline:
   ```yaml
   - name: Build packages
     uses: ranjithrajv/debian-multiarch-builder@v1
     with:
       lintian-check: ${{ github.ref == 'refs/heads/main' }}
   ```

3. **Review warnings regularly**: Even if not failing the build, review warnings periodically

4. **Use pedantic mode for releases**: Enable stricter checks for release builds:
   ```yaml
   lintian:
     pedantic: true  # Only for release builds
   ```

## Workflow Examples

### Basic Usage

```yaml
- name: Build with lintian
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: 'package.yaml'
    version: ${{ inputs.version }}
    build-version: ${{ inputs.build_version }}
    lintian-check: 'true'
```

### Conditional Lintian

Only run lintian on main branch:

```yaml
- name: Build packages
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: 'package.yaml'
    version: ${{ inputs.version }}
    build-version: ${{ inputs.build_version }}
    lintian-check: ${{ github.ref == 'refs/heads/main' }}
```

### User-Controlled Lintian

Allow users to toggle lintian via workflow input:

```yaml
on:
  workflow_dispatch:
    inputs:
      enable_lintian:
        description: 'Run lintian validation'
        type: boolean
        default: true

jobs:
  build:
    steps:
      - name: Build packages
        uses: ranjithrajv/debian-multiarch-builder@v1
        with:
          lintian-check: ${{ inputs.enable_lintian }}
```

## Troubleshooting

### Lintian Not Running

If lintian checks aren't running:

1. Verify the input is set correctly: `lintian-check: 'true'` (must be a string)
2. Check that lintian was installed in the dependencies step
3. Look for warning messages about lintian not being installed

### Build Failing Unexpectedly

If builds fail after enabling lintian:

1. Review the lintian output to identify the errors
2. Temporarily set `fail_on_errors: false` to see all issues without stopping
3. Fix issues one by one, or suppress tags that don't apply

### Too Much Output

If lintian produces too much output:

```yaml
lintian:
  display_level: "error"  # Only show errors
  suppress_tags:
    - tag-name-1
    - tag-name-2
```

## Resources

- [Lintian Official Documentation](https://lintian.debian.org/)
- [Debian Policy Manual](https://www.debian.org/doc/debian-policy/)
- [Lintian Tag List](https://lintian.debian.org/tags.html)
- [Debian New Maintainers' Guide](https://www.debian.org/doc/manuals/maint-guide/)

## See Also

- [Configuration Reference](configuration-reference.md) - Full configuration options
- [Build Summary](build-summary.md) - Understanding build-summary.json
- [Troubleshooting Guide](troubleshooting-guide.md) - Common issues and solutions
