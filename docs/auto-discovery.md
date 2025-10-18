# Auto-Discovery

The action can automatically discover release patterns from GitHub releases, eliminating the need to manually configure `release_pattern` for each architecture.

### How It Works

1. **Fetches release assets** from GitHub API for the specified version
2. **Matches assets** to architectures using common naming patterns
3. **Prefers gnu builds** when available (native to Debian, better performance)
4. **Falls back to musl builds** if gnu not available

### Supported Pattern Matching

| Debian Arch | Matches Upstream Patterns |
|-------------|---------------------------|
| amd64       | x86_64, amd64, x64 |
| arm64       | aarch64, arm64 |
| armel       | arm-, armeabi |
| armhf       | armv7, armhf, arm-.*gnueabihf |
| i386        | i686, i386, x86 |
| ppc64el     | powerpc64le, ppc64le |
| s390x       | s390x |
| riscv64     | riscv64gc, riscv64 |

### When to Use Manual Patterns

Use manual `release_pattern` configuration when:
- Upstream uses non-standard naming conventions
- You need to select a specific variant (e.g., gnu vs musl)
- Release assets don't follow predictable patterns
- You want explicit control over which assets are used

### Example Comparison

**Auto-discovery:**
```yaml
architectures:
  - amd64
  - arm64
  - armhf
```
Discovers: `uv-x86_64-unknown-linux-gnu.tar.gz`, `uv-aarch64-unknown-linux-gnu.tar.gz`, etc.

**Manual:**
```yaml
architectures:
  amd64:
    release_pattern: "uv-x86_64-unknown-linux-musl.tar.gz"  # Specific variant
```
