# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v.0.1a4] - 2026-02-27

### Fixed - Critical Bug Fixes

- **Bash `{version}` parameter expansion corruption** in `discovery.sh` and `discovery-simple.sh`
  - `${pattern//\{version\}/$VERSION}` was appending `/$VERSION}` as literal text instead of substituting
  - The `}` inside `{version}` prematurely closes the outer `${...//...}` expansion
  - Fixed using an intermediate variable: `local _ver='{version}'; pattern="${pattern//$_ver/$VERSION}"`
- **Flat archive extraction failure** in `build.sh`
  - Archives that extract a single file/binary directly (no top-level subdirectory) failed with "Binary source not found"
  - Added archive inspection to detect flat vs. subdirectory layout before extraction
  - For flat archives: creates the expected directory and extracts with `-C extract_dir`
  - Applies to both `tar.gz`/`tgz` and `zip` formats
- **Silent parallel build failures** — builds completing in ~5s with no output
  - `error()` calling `exit 1` inside background subshells bypassed the branch writing the FAILED status file
  - Orchestration loop could not detect which architectures had failed
  - Fixed by adding EXIT trap in `build_architecture_parallel` to guarantee status file is always written
  - Added build log output in final summary before log cleanup to aid debugging
- **SCRIPT_DIR clobbering in library files** causing SIGSEGV / infinite recursion
  - `progress.sh`, `dry-run.sh`, and `zero-config.sh` were overwriting the global `SCRIPT_DIR`
  - Lazy-loader then resolved paths as `src/lib/lib/foo.sh` → not found → called itself → stack overflow
  - Fixed by removing `SCRIPT_DIR=` from `progress.sh`; renamed to private `_DR_LIB_DIR` / `_ZC_LIB_DIR` in other files
- **Source paths missing `/lib/` prefix** in multiple library files
  - `orchestration.sh`, `build.sh`, `validation.sh`, `discovery-simple.sh` referenced `$SCRIPT_DIR/foo.sh`
  - Files live under `$SCRIPT_DIR/lib/`; added missing `/lib/` segment to all affected source calls
- **Dockerfile `sed -i` on gzipped file** corrupting `changelog.Debian.gz`
  - `sed -i` commands were running after `gzip`, writing into the binary compressed data
  - Moved all four `sed -i` operations to before the `gzip` call
- **Demo workflow configuration** (`demo-config.yaml`) using wrong keys and patterns
  - Used unsupported `architecture_map:` key; config parser reads `.architectures`
  - Architecture patterns were wrong (incorrect `{version}` usage, wrong armhf arch string)
  - Fixed to use correct `architectures:` structure with verified asset names from GitHub API

---

## [v.0.1a3] - 2026-02-24

### Added

#### Modular Library System
- New focused libraries extracted from monolithic scripts:
  - **`logging.sh`** — structured output with colour-coded log levels
  - **`progress.sh`** — real-time build progress visualisation with per-arch status
  - **`dry-run.sh`** — 5-step config/version/asset validation without building
  - **`zero-config.sh`** — auto-discovery mode: build from a GitHub repo without a config file
  - **`download-cache.sh`** — download caching between builds
  - **`resource-pool.sh`** — resource-aware parallelism management
  - **`architecture-tracking.sh`** — per-architecture state tracking
  - **`reporting.sh`** — build summary and badge generation
  - **`essential-utils.sh`**, **`file-utils.sh`**, **`package-utils.sh`** — utility helpers

#### CLI Improvements
- `--dry-run` flag — validate config, version, and release assets without building
- `--setup` flag — interactive configuration wizard
- `--auto-discovery` / `--ad` flag — zero-config builds directly from a GitHub repo URL

#### Configuration Templates
- 12+ ready-to-use templates for popular projects:
  - **Rust:** eza, bat, ripgrep, generic
  - **Go:** hugo, kubectl, generic
  - **C/C++:** neovim, generic
  - **Node.js, Python, Ruby:** generic templates
- Template usage guide in `templates/README.md`

#### CI Workflows
- `demo.yml` — build eza as a live demonstration
- `try-it.yml` — one-click zero-config build for any GitHub project
- `setup.yml` — guided configuration generator workflow

#### GitHub API Improvements
- Exponential backoff retry logic (up to 3 attempts)
- Rate-limit detection with automatic wait
- Shared API response cache at `/tmp/github_api_cache`

#### Architecture & Distribution
- Added **loong64** support for Forky and Sid distributions
- Architecture support table in README

### Changed
- Refactored core scripts into focused, single-responsibility modules
- Slimmed down telemetry to a minimal essential implementation
- Removed legacy `utils.sh` in favour of dedicated helper libraries
- Consolidated configuration files under `src/data/`
- Improved `.gitignore` to cover backup files, telemetry data, build summaries, and logs

### Fixed
- Replaced broken `tar -xf` on `.deb` file (`.deb` is `ar` format, not tar)
- Prevented stderr bytes corrupting extracted `.deb` (`2>&1` → `2>/dev/null` on docker run)
- Removed broken `command -v wait -n` check (not valid for bash built-in flags)
- Removed broken float comparison with bash integer operators in orchestration poll loop
- Removed dead `${#pids[@]}` reference to undefined array
- Fixed Docker BuildKit cache path to use consistent `/tmp/docker-cache`
- Fixed `ci-optimization.sh` path in `config.sh`
- Corrected docker layer cache key to use static version instead of `hashFiles`

---

## [v.0.1a2] - 2025-10-17

### Added

- **Parallel architecture builds** — build multiple architectures concurrently (40–60% faster)
  - Configurable via `parallel_builds` and `max_parallel` settings
- **Parallel distribution builds** — build all distributions concurrently per architecture (3–4× faster per arch)
- **Auto-discovery of release patterns** — automatically match release assets from GitHub API
  - Simple list format for architectures: `architectures: [amd64, arm64]`
  - Prefers GNU builds over musl for better Debian compatibility
- **Download caching** — download and extract once per architecture, reuse across all distributions
- **SHA256 checksum verification** — auto-discovers checksum files and verifies archive integrity
- **Build summary JSON** — exports `build-summary.json` with package details, duration, and file sizes
- **Smart defaults from `system.yaml`** — `distributions` and `architectures` are optional in config
- **Lintian integration** — package quality validation against Debian policy
- **Modular codebase** — split monolithic `build.sh` into focused modules under `src/`
  - `utils.sh`, `config.sh`, `github-api.sh`, `discovery.sh`, `validation.sh`, `build.sh`, `orchestration.sh`, `summary.sh`
- **i386 architecture support** — Bookworm only (deprecated in Trixie+)
- **armel lifecycle documentation** — documented as last version in Bookworm as a regular architecture
- **Build observability** — per-architecture timing, completion ratio, total artifact size display
- **`max-parallel` action input** — control concurrent builds directly from workflow input
- **Telemetry and metrics collection** — build duration, memory, CPU, failure classification
- **Enhanced error categorization** — transient vs. permanent detection with remediation suggestions
- **Early version validation** — checks GitHub API before downloading anything
- **Resource monitoring** — CPU and memory usage tracking during builds

### Changed
- Renamed `parallel.sh` → `orchestration.sh` for clarity
- Default max parallel builds increased from 2 to 4
- Documentation restructured into `docs/` directory

### Fixed
- Fixed sed replacement order in Dockerfile (`BUILD_VERSION`/`FULL_VERSION` must precede `VERSION`)
- Fixed `set -e` exiting on background build failures
- Fixed misleading success messages on partial build failures
- Fixed yq lexer errors in telemetry updates
- Installed `jq` and `mikefarah/yq` for correct JSON/YAML parsing

---

## [v.0.1a1] - 2025-10-16

### Added

- Initial release of debian-multiarch-builder action
- Support for 7 architectures: amd64, arm64, armel, armhf, ppc64el, s390x, riscv64
- Support for 4 Debian distributions: bookworm, trixie, forky, sid
- YAML-based configuration with `multiarch-config.yaml`
- Distribution-specific architecture overrides
- Generic `build.sh` script driven by configuration
- Generic Dockerfile template with placeholder substitution
- Architecture-to-release pattern mapping
- Support for tar.gz, tgz, and zip archive formats
- Template files for `DEBIAN/control`, `changelog`, and `copyright`
- Example configurations for lazygit, eza, and uv
- Comprehensive README with usage examples
- MIT License

### Validated
- Successfully built 27 packages for uv (7 architectures × 4 distributions, minus riscv64 on bookworm)
- Published to GitHub Marketplace
