# Optimization Design: Speed & Reliability

**Date:** 2026-02-24
**Goal:** Make `debian-multiarch-builder` the go-to choice for speed and reliability in the GitHub Actions marketplace.

---

## Problem Statement

The current workflow runs all 9 architectures inside a single GitHub Actions runner job, either sequentially or via a broken "parallel" mode. Total build time is roughly the **sum** of all arch build times. Additionally, Docker layers are never cached between runs, and several bugs in the parallel orchestration cause silent failures.

---

## Solution Overview

Three coordinated changes:

1. **GitHub Actions matrix strategy** — one runner per architecture
2. **Docker layer caching via `actions/cache`** — faster re-runs
3. **Script reliability bug fixes** — eliminate silent failures

---

## Design

### 1. GitHub Actions Matrix Workflow

**File:** `examples/workflow-example.yml`

Replace the single `build` job with a matrix job, one runner per architecture. Use `fail-fast: false` so one arch failure doesn't cancel the rest. Merge artifacts in the release job.

```yaml
jobs:
  build:
    name: Build (${{ matrix.arch }})
    runs-on: ubuntu-latest
    strategy:
      matrix:
        arch: [amd64, arm64, armel, armhf, i386, ppc64el, s390x, riscv64, loong64]
      fail-fast: false

    steps:
      - uses: actions/checkout@v4

      - name: Restore Docker cache
        uses: actions/cache@v4
        with:
          path: /tmp/docker-cache
          key: docker-${{ matrix.arch }}-${{ hashFiles('src/Dockerfile') }}
          restore-keys: docker-${{ matrix.arch }}-

      - uses: ranjithrajv/debian-multiarch-builder@v1
        with:
          config-file: multiarch-config.yaml
          version: ${{ inputs.version }}
          build-version: ${{ inputs.build_version }}
          architecture: ${{ matrix.arch }}

      - name: Save Docker cache
        uses: actions/cache@v4
        if: always()
        with:
          path: /tmp/docker-cache
          key: docker-${{ matrix.arch }}-${{ hashFiles('src/Dockerfile') }}

      - uses: actions/upload-artifact@v4
        with:
          name: debian-packages-${{ matrix.arch }}
          path: '*.deb'

  release:
    name: Create Draft Release
    needs: build
    if: github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          pattern: debian-packages-*
          merge-multiple: true
      - uses: softprops/action-gh-release@v2
        with:
          draft: true
          files: '*.deb'
          name: ${{ inputs.version }}+${{ inputs.build_version }}
          tag_name: ${{ inputs.version }}
          fail_on_unmatched_files: true
```

**Speed impact:** 9 jobs run simultaneously. Total build time = max(single arch build time) instead of sum.

---

### 2. Docker Layer Caching

**File:** `src/lib/build.sh`

**Current (broken):**
```bash
--cache-from "type=local,src=/tmp/docker-cache-shared"     # always empty
--cache-to "type=local,dest=${cache_dir},mode=max"          # per-arch-dist subdir, not read back
```

**Fixed:**
```bash
--cache-from "type=local,src=/tmp/docker-cache"
--cache-to "type=local,dest=/tmp/docker-cache,mode=max"
```

Use a single consistent path `/tmp/docker-cache`. The `actions/cache` step in the workflow restores this directory before the build and saves it after (keyed by `docker-{arch}-{Dockerfile hash}`). `mode=max` caches all intermediate layers.

---

### 3. Script Bug Fixes

#### Bug 1: `tar -xf` on `.deb` file (`src/lib/build.sh:109`)

**Problem:** `.deb` files are `ar` archives, not tar. This call always fails, causing `build_distribution` to return 1 on every successful build.

**Current:**
```bash
if ! tar -xf "./${PACKAGE_NAME}_${FULL_VERSION}.deb" 2>&1; then
    return 1
fi
```

**Fix:** Replace with a file existence and non-zero size check:
```bash
if [ ! -s "./${PACKAGE_NAME}_${FULL_VERSION}.deb" ]; then
    return 1
fi
```

#### Bug 2: `wait -n` detection (`src/lib/orchestration.sh:158`)

**Problem:** `command -v wait -n` does not check if bash supports `wait -n` (bash 4.3+ feature). It checks for a command named `-n`.

**Current:**
```bash
if command -v wait -n >/dev/null 2>&1; then
    wait -n || wait_result=$?
```

**Fix:** Check bash version directly. GitHub Actions runners use bash 5.x, so `wait -n` is always available — simplify by removing the fallback:
```bash
wait -n || wait_result=$?
```

#### Bug 3: Float comparison in bash (`src/lib/orchestration.sh:264`)

**Problem:** `[ "$sleep_duration" -lt "$max_sleep" ]` fails when `sleep_duration=0.1`. Bash `[` uses integer comparison only.

**Fix:** Remove the broken exponential backoff block entirely. Use a fixed `sleep 1` between polling iterations.

#### Bug 4: Undefined `pids` array (`src/lib/orchestration.sh:257`)

**Problem:** `${#pids[@]}` references an array that is never declared in that scope — dead code.

**Fix:** Remove the block. Job tracking is handled by `jobs -p` / `get_running_jobs()`.

---

## Files Changed

| File | Change |
|------|--------|
| `examples/workflow-example.yml` | Rewrite with matrix + Docker cache + artifact merge |
| `src/lib/build.sh` | Fix Docker cache path, fix `tar -xf` bug |
| `src/lib/orchestration.sh` | Fix `wait -n` detection, remove float comparison, remove undefined `pids` |

---

## Expected Outcomes

| Metric | Before | After |
|--------|--------|-------|
| 9-arch build time | ~sum of all arches (~40-60 min) | ~longest single arch (~8-12 min) |
| Docker layer cache hits | Never (always cold) | ~80% hit rate after first run |
| `build_distribution` reliability | Always returns 1 (tar bug) | Returns correct exit code |
| Parallel orchestration | Broken float/wait bugs | Stable |
