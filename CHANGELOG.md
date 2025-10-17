# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Auto-discovery of release patterns** - Automatically discover release assets from GitHub
  - Simple list format for architectures (e.g., `architectures: [amd64, arm64]`)
  - Fetches release assets from GitHub API
  - Smart pattern matching for common architecture names
  - Prefers gnu builds over musl (native to Debian, better performance)
  - Backward compatible with manual `release_pattern` configuration
  - Significantly reduces configuration complexity
- **Parallel architecture builds** - Build multiple architectures concurrently (40-60% faster)
  - Configurable with `parallel_builds` and `max_parallel` settings
  - Default: 2 concurrent architecture builds
- **Parallel distribution builds** - Build all distributions concurrently for each architecture (3-4x faster per architecture)
  - Automatically enabled - builds bookworm, trixie, forky, sid in parallel
  - Combines with parallel architecture builds for maximum throughput
- **Download caching** - Download and extract once per architecture, reuse for all distributions
  - Eliminates redundant downloads (previously downloaded 4 times per architecture)
  - Significantly reduces bandwidth usage and build time
- **i386 architecture support** - Added support for i386 (Bookworm only)
- **armel lifecycle documentation** - Documented armel end-of-life (last release in Trixie)
- **Documentation restructure** - Organized docs into `docs/` directory
  - Created `docs/MIGRATION.md` for migration guides
  - Moved `docs/USAGE.md` and `docs/TROUBLESHOOTING.md`
  - Added CONTRIBUTING.md with contribution guidelines
  - Added GitHub issue templates (bug report, feature request, documentation)
- Distribution-specific architecture example configuration
- Comprehensive error messages with helpful diagnostics
- Color-coded output (errors in red, success in green, warnings in yellow, info in blue)
- Pre-flight validation of all configuration requirements
- Validation of upstream release existence before downloading
- Progress indicators showing N/M architectures being built
- Package size display in final summary
- Validation of YAML syntax
- Validation of GitHub repo format
- Validation of architecture existence before building
- Check for required tools (yq, docker)
- Check for Docker daemon availability
- Detailed error messages showing:
  - Missing configuration fields
  - Invalid YAML syntax
  - Non-existent upstream releases with GitHub link
  - Binary source path issues with directory listing
  - Docker build failures with troubleshooting hints

### Changed
- README.md now references docs in `docs/` directory
- Architecture table includes distribution-specific notes
- Improved help message with better formatting and examples
- Enhanced logging throughout the build process
- Better error context when downloads or extractions fail
- Download progress now shown with wget --show-progress

### Fixed
- **Critical:** Fixed sed replacement order bug in Dockerfile
  - BUILD_VERSION and FULL_VERSION must be replaced before VERSION
  - Prevents incorrect version string substitution
- Fixed README.md optional file copy in Dockerfile
- Better handling of missing binary paths in extracted archives
- More robust error checking for all file operations

## [v.0.1a1] - 2025-10-16

### Added
- Initial release of debian-multiarch-builder action
- Support for 7 architectures (amd64, arm64, armel, armhf, ppc64el, s390x, riscv64)
- Support for 4 Debian distributions (bookworm, trixie, forky, sid)
- YAML-based configuration with `multiarch-config.yaml`
- Distribution-specific architecture overrides
- Generic build.sh script driven by configuration
- Generic Dockerfile template with placeholder substitution
- Architecture-to-release pattern mapping
- Support for tar.gz, tgz, and zip archive formats
- Template files for DEBIAN/control, changelog, and copyright
- Example configurations for lazygit, eza, and uv
- Comprehensive README with usage examples
- MIT License

### Validated
- Successfully built 27 packages for uv (7 architectures × 4 distributions, minus riscv64 on bookworm)
- Published to GitHub Marketplace
- Proven in production use

[Unreleased]: https://github.com/ranjithrajv/debian-multiarch-builder/compare/v.0.1a1...HEAD
[v.0.1a1]: https://github.com/ranjithrajv/debian-multiarch-builder/releases/tag/v.0.1a1
