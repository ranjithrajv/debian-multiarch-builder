# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
- Improved help message with better formatting and examples
- Enhanced logging throughout the build process
- Better error context when downloads or extractions fail
- Download progress now shown with wget --show-progress

### Fixed
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
