# Performance

### Multi-Level Parallelization

The action implements **two levels of parallelization** for maximum performance:

1. **Parallel Architecture Builds** - Multiple architectures build concurrently (configurable)
2. **Parallel Distribution Builds** - All distributions build concurrently within each architecture (automatic)
3. **Download Caching** - Download once per architecture, reuse for all distributions

### Performance Features

- **Default behavior:** 2 concurrent architecture builds, unlimited concurrent distributions
- **Time savings:** 70-80% faster than fully sequential builds
- **Example:** Building 8 architectures × 4 distributions (32 packages):
  - Sequential: ~30 minutes
  - Current optimizations: ~5-7 minutes

### Configuration

```yaml
# Optional: customize parallel build settings
parallel_builds:
  architectures:
    enabled: true        # Default: true
    max_concurrent: 2    # Default: 2 (concurrent architecture builds)
  distributions:
    enabled: true        # Default: true (build distributions in parallel per arch)
```

**Recommendations:**
- GitHub Actions standard runners: `max_concurrent: 2` (2 CPU cores)
- Self-hosted runners with 4+ cores: `max_concurrent: 4`
- Sequential architecture builds: Set `architectures.enabled: false`
- Sequential distribution builds: Set `distributions.enabled: false` (slower but uses less resources)

### Performance Comparison

| Configuration | 8 Archs × 4 Dists (32 packages) | Time Savings |
|---------------|----------------------------------|--------------|
| Fully Sequential | ~30 minutes | baseline |
| Parallel Archs (2) Only | ~15 minutes | 50% faster |
| Parallel Archs (2) + Parallel Dists | ~5-7 minutes | 75-80% faster |
| Parallel Archs (4) + Parallel Dists | ~3-4 minutes | 85-90% faster |

**Key Optimizations:**
- **Download Caching**: Previously downloaded 4× per architecture (once per distribution), now downloads once
- **Parallel Distributions**: Previously built distributions sequentially, now builds all 4 simultaneously
- **Combined Effect**: Reduces per-architecture build time from ~4 minutes to ~1 minute
