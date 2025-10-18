# Build Output & Observability

The action provides detailed real-time feedback during builds with enhanced observability features to help you monitor progress, identify issues, and track build metrics.

## Features Overview

- **Per-architecture build timing** - See exactly how long each architecture takes to build
- **Progress indicators** - Track completion status with X/Y counters and running architecture lists
- **Enhanced error summaries** - Clean, actionable error messages without log noise
- **Artifact size tracking** - Monitor total package sizes in human-readable format
- **Build metrics in JSON** - Structured build data for automation and monitoring

## Per-Architecture Build Timing

Each architecture build displays its duration, helping identify slow builds and track performance over time.

### Example Output

```
🔨 Starting build for amd64 (0/8)...
🔨 Starting build for arm64 (1/8)...
✅ Completed build for amd64 (1m36s) [1/8]
✅ Completed build for arm64 (1m37s) [2/8]
✅ Completed build for armhf (1m30s) [3/8]
✅ Completed build for ppc64el (1m29s) [4/8]
✅ Completed build for s390x (57s) [5/8]
✅ Completed build for i386 (56s) [6/8]
✅ Completed build for armel (40s) [7/8]
✅ Completed build for riscv64 (39s) [8/8]
```

### Benefits

- **Identify slow architectures** - Quickly spot which builds take the longest
- **Track performance changes** - Monitor how build times change with different versions
- **Debug performance issues** - Correlate slow builds with upstream changes or infrastructure issues
- **Optimize parallelism** - Use timing data to tune max-parallel settings

### Use Cases

**Performance monitoring:**
```bash
# Compare build times across versions
grep "Completed build for amd64" build-logs/*.log
# Output: amd64 went from 1m36s to 2m15s - investigate upstream changes
```

**Capacity planning:**
```bash
# Check if increasing max-parallel would help
# If builds are: 1m36s, 1m37s, 1m30s, 1m29s, 57s, 56s, 40s, 39s
# Average: ~1min, so 4 concurrent would cut time in half
```

## Progress Indicators

Real-time progress tracking shows completion status and currently running builds.

### Example Output

```
⚡ Parallel builds enabled (max: 2 concurrent)

✅ Completed build for amd64 (1m36s) [1/8]
🔨 Starting build for armhf (3/8)...
   ⚡ Running: arm64 armhf
✅ Completed build for arm64 (1m37s) [2/8]
🔨 Starting build for ppc64el (4/8)...
   ⚡ Running: armhf ppc64el
✅ Completed build for armhf (1m30s) [3/8]
```

### Features

- **Completion ratio** - `[3/8]` shows completed/total architectures
- **Running builds** - `⚡ Running: armhf ppc64el` lists currently building architectures
- **Start order** - `(3/8)` shows the start sequence number
- **Clear pipeline status** - See at a glance what's running, what's done, what's pending

### Benefits

- **Real-time visibility** - Know exactly what's happening at any moment
- **Pipeline monitoring** - Watch the build pipeline progress through all architectures
- **Troubleshooting** - Identify stuck builds quickly
- **Capacity verification** - Confirm max-parallel setting is working as expected

## Enhanced Error Summaries

Clean, actionable error messages instead of verbose log dumps.

### Example Output

**Success:**
```
✅ Total: 25 packages
✅ Build summary saved to build-summary.json
   📦 Total artifact size: 315 MB (25 packages)
```

**Failure:**
```
==========================================
❌ Build Summary: 2 failed, 6 succeeded
==========================================

Failed architectures:
  • ppc64el
  • s390x
```

### Improvements

**Before (verbose log dumps):**
- 100+ lines of Docker build output per failure
- Hard to identify which architectures failed
- Mixed success/failure messages
- Difficult to scan quickly

**After (clean summaries):**
- Clear success/failure counts at the top
- Concise list of failed architectures
- Actionable information without noise
- Easy to scan and understand

### Benefits

- **Quick failure identification** - See failed architectures immediately
- **Better CI/CD logs** - Clean output in GitHub Actions
- **Easier debugging** - Focus on what matters
- **Professional appearance** - Clean, organized output

## Artifact Size Tracking

Total package size displayed at build completion in human-readable format.

### Example Output

```
✅ Build summary saved to build-summary.json
   📦 Total artifact size: 315 MB (25 packages)
```

### Use Cases

**Monitor package size growth:**
```bash
# Track size changes across versions
v0.9.1: 📦 Total artifact size: 280 MB (25 packages)
v0.9.2: 📦 Total artifact size: 298 MB (25 packages)
v0.9.3: 📦 Total artifact size: 315 MB (25 packages)
# Size increasing - investigate upstream binary size changes
```

**Verify expected sizes:**
```bash
# Ensure packages are within reasonable limits
if [ total_size_mb -gt 500 ]; then
  echo "Warning: Package size exceeds 500 MB"
fi
```

**Track storage requirements:**
```bash
# Calculate repository storage needs
# 315 MB × 10 versions = 3.15 GB storage needed
```

### Build Summary JSON

Artifact sizes are also available in structured format:

```json
{
  "total_size_bytes": 330301440,
  "total_size_human": "315 MB",
  "packages": [
    {"name": "uv_0.9.3-1+bookworm_amd64.deb", "size": 12845632},
    {"name": "uv_0.9.3-1+trixie_amd64.deb", "size": 12845632}
  ]
}
```

**Programmatic access:**
```bash
# Get total size in MB
jq '.total_size_bytes / 1024 / 1024' build-summary.json

# Find largest package
jq '.packages | sort_by(.size) | reverse | .[0]' build-summary.json

# Calculate average package size
jq '[.packages[].size] | add / length' build-summary.json
```

## Complete Build Output Example

Here's what a complete successful build looks like with all observability features:

```
🚀 Building uv 0.9.3-1 for all supported architectures...
⚡ Parallel builds enabled (max: 2 concurrent)

🔨 Starting build for amd64 (0/8)...
🔨 Starting build for arm64 (1/8)...
=========================================
ℹ️  Building for architecture: amd64
ℹ️  Release pattern: uv-x86_64-unknown-linux-gnu.tar.gz
=========================================
=========================================
ℹ️  Building for architecture: arm64
ℹ️  Release pattern: uv-aarch64-unknown-linux-gnu.tar.gz
=========================================

✅ Completed build for amd64 (1m36s) [1/8]
🔨 Starting build for armhf (3/8)...
   ⚡ Running: arm64 armhf

✅ Completed build for arm64 (1m37s) [2/8]
🔨 Starting build for ppc64el (4/8)...
   ⚡ Running: armhf ppc64el

✅ Completed build for armhf (1m30s) [3/8]
🔨 Starting build for s390x (5/8)...
   ⚡ Running: ppc64el s390x

✅ Completed build for ppc64el (1m29s) [4/8]
🔨 Starting build for i386 (6/8)...
   ⚡ Running: s390x i386

✅ Completed build for s390x (57s) [5/8]
🔨 Starting build for armel (7/8)...
   ⚡ Running: i386 armel

✅ Completed build for i386 (56s) [6/8]
🔨 Starting build for riscv64 (8/8)...
   ⚡ Running: armel riscv64

✅ Completed build for armel (40s) [7/8]
✅ Completed build for riscv64 (39s) [8/8]

✅ Total: 25 packages
✅ Build summary saved to build-summary.json
   📦 Total artifact size: 315 MB (25 packages)
```

## Controlling Observability

### Adjust Parallelism

Control concurrent builds to match your infrastructure:

```yaml
# In your workflow
- uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    max-parallel: '4'  # More concurrency = faster builds
```

**Recommendations:**
- GitHub Actions runners (2 cores): `max-parallel: 2`
- Self-hosted runners (4+ cores): `max-parallel: 4`
- High-memory runners (8+ cores): `max-parallel: 8`

### Monitor Build Performance

Track build metrics over time:

```bash
# Extract build duration from summary JSON
BUILD_TIME=$(jq '.build_duration_seconds' build-summary.json)
echo "Build took ${BUILD_TIME}s"

# Track across multiple builds
echo "$(date),${BUILD_TIME}" >> build-metrics.csv
```

### Integration with CI/CD

Use observability features in automation:

```yaml
- name: Build packages
  id: build
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: 'package.yaml'
    version: ${{ inputs.version }}
    build-version: ${{ inputs.build_version }}

- name: Check build metrics
  run: |
    TOTAL_SIZE=$(jq -r '.total_size_human' build-summary.json)
    DURATION=$(jq '.build_duration_seconds' build-summary.json)

    echo "::notice::Built $TOTAL_SIZE in ${DURATION}s"

    # Fail if build too slow
    if [ $DURATION -gt 600 ]; then
      echo "::error::Build took longer than 10 minutes"
      exit 1
    fi
```

## Troubleshooting

### No build timing shown

**Symptom:** Builds complete but don't show duration

**Cause:** Very old action version

**Solution:** Update to latest version:
```yaml
uses: ranjithrajv/debian-multiarch-builder@v1  # or @main for latest
```

### Progress shows wrong concurrency

**Symptom:** Says "max: 2 concurrent" but only 1 runs at a time

**Cause:** Not enough architectures queued, or system resource limits

**Solution:**
- Check if you're only building 1 architecture
- Verify system has enough resources (CPU/memory)
- Check Docker daemon capacity

### Artifact size shows 0 MB

**Symptom:** Total artifact size shows "0 MB" or "0 KB"

**Cause:** No packages were built successfully

**Solution:**
- Check for build failures above the summary
- Review architecture error messages
- Verify upstream releases exist

## Best Practices

1. **Monitor build times** - Track per-architecture timing to identify performance regressions
2. **Tune parallelism** - Adjust max-parallel based on your infrastructure and build times
3. **Watch artifact sizes** - Set up alerts if package sizes grow unexpectedly large
4. **Parse build-summary.json** - Use structured data for automation and monitoring
5. **Archive build logs** - Keep logs with timing data for historical analysis

## See Also

- [Performance Configuration](../README.md#performance) - Tuning parallel builds
- [Build Summary](../README.md#build-summary) - JSON structure and fields
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues and solutions
