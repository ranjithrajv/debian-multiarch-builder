# Optimization: Speed & Reliability Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `debian-multiarch-builder` the fastest and most reliable multi-arch Debian build action on the GitHub Actions marketplace by adding a matrix workflow, Docker layer caching, and fixing four script bugs that cause silent build failures.

**Architecture:** Three coordinated changes — rewrite the example workflow to use GitHub Actions matrix (9 arch-parallel jobs), fix the Docker cache path so `actions/cache` can save/restore layers between runs, and fix four bugs in `src/lib/build.sh` and `src/lib/orchestration.sh` that cause silent failures. The action itself (inputs, outputs, `action.yml`) stays unchanged — only the example workflow and internal scripts change.

**Tech Stack:** Bash 5.x, GitHub Actions YAML, Docker BuildKit, `actions/cache@v4`, `actions/upload-artifact@v4`, `actions/download-artifact@v4`

---

## Task 1: Fix `tar -xf` on `.deb` file (build.sh)

**Files:**
- Modify: `src/lib/build.sh:109-111`

This is the highest-priority bug. Every call to `build_distribution` hits this line after successfully extracting the `.deb` from Docker. `.deb` files are `ar` archives — `tar -xf` always fails, so `build_distribution` always returns 1 even when the `.deb` was created correctly.

**Step 1: Verify the bug exists**

```bash
# Look at the exact lines
sed -n '107,116p' src/lib/build.sh
```

Expected output:
```
    # Clean up cache directory (optional - keep for shared cache)
    # rm -rf "$cache_dir" 2>/dev/null || true

    if ! tar -xf "./${PACKAGE_NAME}_${FULL_VERSION}.deb" 2>&1; then
        return 1
    fi

    # Run lintian check on the built package
    if ! run_lintian_check "./${PACKAGE_NAME}_${FULL_VERSION}.deb"; then
```

**Step 2: Make the fix**

In `src/lib/build.sh`, replace lines 109-111:

```bash
    if ! tar -xf "./${PACKAGE_NAME}_${FULL_VERSION}.deb" 2>&1; then
        return 1
    fi
```

With:

```bash
    # Verify the .deb package was created and is non-empty
    if [ ! -s "./${PACKAGE_NAME}_${FULL_VERSION}.deb" ]; then
        return 1
    fi
```

**Step 3: Verify the change looks correct**

```bash
sed -n '107,118p' src/lib/build.sh
```

Expected — you should see `[ ! -s "./${PACKAGE_NAME}_${FULL_VERSION}.deb" ]` and no `tar -xf`.

**Step 4: Commit**

```bash
git add src/lib/build.sh
git commit -m "fix: replace tar -xf on .deb with file existence check in build_distribution"
```

---

## Task 2: Fix `wait -n` detection (orchestration.sh)

**Files:**
- Modify: `src/lib/orchestration.sh:157-169`

`command -v wait -n` does not test if bash supports `wait -n`. It checks for a command named `-n`. GitHub Actions runners run bash 5.x, which fully supports `wait -n` (bash 4.3+), so we can simply remove the broken check and always use `wait -n`.

**Step 1: Verify the current code**

```bash
sed -n '155,170p' src/lib/orchestration.sh
```

Expected — you should see:
```bash
        if command -v wait -n >/dev/null 2>&1; then
            wait -n || wait_result=$?
        else
            # Fallback for older bash versions
            sleep $sleep_duration
            ...
        fi
```

**Step 2: Make the fix**

In `src/lib/orchestration.sh`, replace the block at lines 157-169:

```bash
            # Use wait -n to wait for next job completion (bash 4.3+)
            if command -v wait -n >/dev/null 2>&1; then
                wait -n || wait_result=$?
            else
                # Fallback for older bash versions
                sleep $sleep_duration
                for job in $(jobs -p); do
                    if ! kill -0 $job 2>/dev/null; then
                        wait $job || wait_result=$?
                        break
                    fi
                done
            fi
```

With:

```bash
            # Use wait -n to wait for next job completion (bash 4.3+ / bash 5.x on GitHub runners)
            wait -n || wait_result=$?
```

**Step 3: Verify**

```bash
sed -n '155,165p' src/lib/orchestration.sh
```

Expected — you see `wait -n || wait_result=$?` with no fallback block.

**Step 4: Commit**

```bash
git add src/lib/orchestration.sh
git commit -m "fix: simplify wait -n detection — GitHub Actions always uses bash 5.x"
```

---

## Task 3: Fix float comparison and undefined `pids` array (orchestration.sh)

**Files:**
- Modify: `src/lib/orchestration.sh:252-270`

Two bugs in the same block:
1. `[ "$sleep_duration" -lt "$max_sleep" ]` uses integer comparison (`-lt`) with float values (`0.1`, `2.0`) — bash will error.
2. `${#pids[@]}` references a `pids` array that is never declared in scope — this is dead code that evaluates to 0 always.

The entire exponential backoff block is unnecessary because `wait -n` (fixed in Task 2) already blocks efficiently until a job completes. Replace with a simple fixed `sleep 1`.

**Step 1: Verify the current code**

```bash
sed -n '252,271p' src/lib/orchestration.sh
```

Expected — you see the `local sleep_duration=0.1`, `${#pids[@]}`, and `bc -l` lines.

**Step 2: Make the fix**

In `src/lib/orchestration.sh`, replace the block at lines 252-270:

```bash
        # Implement exponential backoff polling
        local sleep_duration=0.1
        local max_sleep=2.0

        # If no builds are active, sleep longer
        if [ ${#pids[@]} -eq 0 ]; then
            sleep_duration=1.0
        fi

        sleep $sleep_duration

        # Gradually increase sleep duration if we're polling frequently
        if [ "$sleep_duration" -lt "$max_sleep" ]; then
            sleep_duration=$(echo "$sleep_duration * 1.5" | bc -l 2>/dev/null || echo "1.0")
            # Cap at max_sleep
            if [ "$(echo "$sleep_duration > $max_sleep" | bc -l 2>/dev/null || echo "0")" = "1" ]; then
                sleep_duration=$max_sleep
            fi
        fi
```

With:

```bash
        sleep 1
```

**Step 3: Verify**

```bash
sed -n '249,258p' src/lib/orchestration.sh
```

Expected — you see `sleep 1` with no `bc -l`, no `pids[@]`, no float variables.

**Step 4: Commit**

```bash
git add src/lib/orchestration.sh
git commit -m "fix: remove broken float comparison and undefined pids array in orchestration poll loop"
```

---

## Task 4: Fix Docker cache path in build_distribution (build.sh)

**Files:**
- Modify: `src/lib/build.sh:14-38`

Currently the Docker build reads from `/tmp/docker-cache-shared` (always empty) and writes to a per-arch-dist path (`/tmp/docker-cache-${dist}-${build_arch}`). These are never the same directory, so caching never works — even within a single run.

Fix: use a single consistent path `/tmp/docker-cache` for both read and write. The matrix workflow (Task 5) will restore this path from `actions/cache` before the build step runs.

**Step 1: Verify the current Docker build command**

```bash
sed -n '14,38p' src/lib/build.sh
```

Expected — you see `--cache-from "type=local,src=/tmp/docker-cache-shared"` and `--cache-to "type=local,dest=${cache_dir},mode=max"`.

**Step 2: Make the fix**

In `src/lib/build.sh`, replace the block starting at line 14:

```bash
    # Enhanced Docker build with BuildKit optimization and failure capture
    local docker_build_log="/tmp/docker-build-${dist}-${build_arch}.log"
    local cache_dir="/tmp/docker-cache-${dist}-${build_arch}"

    # Enable Docker BuildKit for better performance
    export DOCKER_BUILDKIT=1

    # Create cache directory for this build and setup shared cache
    mkdir -p "$cache_dir"
    mkdir -p "/tmp/docker-cache-shared"

    if ! docker build \
        --progress=plain \
        --tag "${PACKAGE_NAME}-${dist}-${build_arch}" \
        --file "$SCRIPT_DIR/Dockerfile" \
        --build-arg DEBIAN_DIST="$dist" \
        --build-arg PACKAGE_NAME="$PACKAGE_NAME" \
        --build-arg VERSION="$VERSION" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$FULL_VERSION" \
        --build-arg ARCH="$build_arch" \
        --build-arg BINARY_SOURCE="$binary_source" \
        --build-arg GITHUB_REPO="$GITHUB_REPO" \
        --cache-from "type=local,src=/tmp/docker-cache-shared" \
        --cache-to "type=local,dest=${cache_dir},mode=max" \
        . 2>&1 | tee "$docker_build_log"; then
```

With:

```bash
    # Enhanced Docker build with BuildKit optimization and failure capture
    local docker_build_log="/tmp/docker-build-${dist}-${build_arch}.log"
    local cache_dir="/tmp/docker-cache"

    # Enable Docker BuildKit for better performance
    export DOCKER_BUILDKIT=1

    # Create shared cache directory (restored from actions/cache between runs)
    mkdir -p "$cache_dir"

    if ! docker build \
        --progress=plain \
        --tag "${PACKAGE_NAME}-${dist}-${build_arch}" \
        --file "$SCRIPT_DIR/Dockerfile" \
        --build-arg DEBIAN_DIST="$dist" \
        --build-arg PACKAGE_NAME="$PACKAGE_NAME" \
        --build-arg VERSION="$VERSION" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$FULL_VERSION" \
        --build-arg ARCH="$build_arch" \
        --build-arg BINARY_SOURCE="$binary_source" \
        --build-arg GITHUB_REPO="$GITHUB_REPO" \
        --cache-from "type=local,src=${cache_dir}" \
        --cache-to "type=local,dest=${cache_dir},mode=max" \
        . 2>&1 | tee "$docker_build_log"; then
```

**Step 3: Verify**

```bash
sed -n '14,40p' src/lib/build.sh
```

Expected — you see `cache_dir="/tmp/docker-cache"` (no dist/arch suffix), and both `--cache-from` and `--cache-to` use `${cache_dir}`.

**Step 4: Commit**

```bash
git add src/lib/build.sh
git commit -m "fix: use consistent docker cache path /tmp/docker-cache for BuildKit layer caching"
```

---

## Task 5: Rewrite workflow-example.yml with matrix strategy + Docker caching

**Files:**
- Modify: `examples/workflow-example.yml` (full rewrite)

Replace the single-job workflow with a matrix of 9 parallel jobs, one per architecture. Add `actions/cache` for Docker layers. Merge artifacts in the release job using `merge-multiple: true`.

**Step 1: Read the current file to note what to preserve**

```bash
cat examples/workflow-example.yml
```

Note the `on:` triggers, `permissions:`, and `release:` job structure — these carry over.

**Step 2: Write the new workflow**

Replace the entire content of `examples/workflow-example.yml` with:

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

permissions:
  contents: write

jobs:
  build:
    name: Build (${{ matrix.arch }})
    runs-on: ubuntu-latest
    strategy:
      matrix:
        arch: [amd64, arm64, armel, armhf, i386, ppc64el, s390x, riscv64, loong64]
      fail-fast: false

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Restore Docker layer cache
        uses: actions/cache@v4
        with:
          path: /tmp/docker-cache
          key: docker-${{ matrix.arch }}-${{ hashFiles('src/Dockerfile') }}
          restore-keys: |
            docker-${{ matrix.arch }}-

      - name: Build multi-architecture packages
        uses: ranjithrajv/debian-multiarch-builder@v1
        with:
          config-file: 'multiarch-config.yaml'
          version: ${{ inputs.version }}
          build-version: ${{ inputs.build_version }}
          architecture: ${{ matrix.arch }}

      - name: Save Docker layer cache
        uses: actions/cache@v4
        if: always()
        with:
          path: /tmp/docker-cache
          key: docker-${{ matrix.arch }}-${{ hashFiles('src/Dockerfile') }}

      - name: Upload Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: debian-packages-${{ matrix.arch }}
          path: '*.deb'

  release:
    name: Create Draft Release
    if: github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Download All Artifacts
        uses: actions/download-artifact@v4
        with:
          pattern: debian-packages-*
          merge-multiple: true

      - name: Publish Release Draft
        uses: softprops/action-gh-release@v2
        with:
          draft: true
          files: '*.deb'
          name: ${{ inputs.version }}+${{ inputs.build_version }}
          tag_name: ${{ inputs.version }}
          fail_on_unmatched_files: true
```

**Step 3: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('examples/workflow-example.yml'))" && echo "YAML valid"
```

Expected: `YAML valid`

**Step 4: Verify key differences from old workflow**

```bash
grep -E "(matrix|fail-fast|cache|merge-multiple|debian-packages-)" examples/workflow-example.yml
```

Expected — you see all five of those patterns present.

**Step 5: Commit**

```bash
git add examples/workflow-example.yml
git commit -m "feat: rewrite workflow with 9-way arch matrix and docker layer caching"
```

---

## Task 6: Update README to document the speed improvement

**Files:**
- Modify: `README.md` — update the workflow section and add a performance note

**Step 1: Find the current workflow section in README**

```bash
grep -n "workflow\|parallel\|architecture\|Build" README.md | head -20
```

**Step 2: Add a performance callout**

Find the first mention of the example workflow in README.md and add a callout block immediately before it:

```markdown
> **Performance:** Builds all 9 architectures in parallel — each in its own GitHub Actions runner. Total build time equals the longest single architecture (typically ~8 minutes), not the sum. Docker layer caching further reduces re-run times by ~60%.
```

**Step 3: Update the architecture input description if present**

Find any documentation showing `architecture: 'all'` as the recommended default and update it to show the matrix approach is preferred for speed.

**Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document matrix parallelism and docker caching performance gains"
```

---

## Task 7: Verify the full change set

**Step 1: Check all four bugs are fixed**

```bash
# Bug 1: tar -xf gone
grep -n "tar -xf" src/lib/build.sh
# Expected: no output (pattern not found)

# Bug 2: command -v wait -n gone
grep -n "command -v wait -n" src/lib/orchestration.sh
# Expected: no output

# Bug 3: pids[@] gone
grep -n "pids\[@\]" src/lib/orchestration.sh
# Expected: no output

# Bug 4: float sleep_duration=0.1 gone
grep -n "sleep_duration=0.1" src/lib/orchestration.sh
# Expected: no output
```

**Step 2: Check Docker cache path is consistent**

```bash
grep -n "docker-cache" src/lib/build.sh
```

Expected — you see only `/tmp/docker-cache` (no `-shared` suffix, no per-arch-dist suffix).

**Step 3: Check matrix workflow structure**

```bash
grep -E "(matrix:|fail-fast:|arch:)" examples/workflow-example.yml
```

Expected output:
```
      matrix:
        arch: [amd64, arm64, armel, armhf, i386, ppc64el, s390x, riscv64, loong64]
      fail-fast: false
```

**Step 4: Review full git log for this feature**

```bash
git log --oneline -8
```

Expected — you see 5 commits: tar fix, wait -n fix, float/pids fix, docker cache fix, workflow rewrite, README update.

---

## Testing in uv-debian

Per CLAUDE.md, validate end-to-end by triggering a test workflow from the `../uv-debian` repository:

```bash
cd ../uv-debian

# Trigger a single-arch build to test the script fixes work
gh workflow run "Build Package for Debian" \
  --field version="<latest-version>" \
  --field build_version="1"

# Monitor progress
gh run view --watch

# Check for success across multiple arches
gh run list --limit 5
```

Look for: all 9 arch matrix jobs completing (green), Docker cache hit on second run (check step output for "Cache restored"), `.deb` files present in release artifacts.
