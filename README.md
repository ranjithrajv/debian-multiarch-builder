# Debian Multi-Architecture Package Builder

A reusable GitHub Action for building Debian packages across multiple architectures from upstream releases. This action simplifies the process of creating multi-architecture Debian packages for projects distributed via GitHub releases.

## Why Use This Action?

*   **Simplify Your Workflow:** Instead of wrestling with complex build scripts, you can build your Debian packages with a single, easy-to-use GitHub Action.
*   **Save Time:** With multi-level parallelization and download caching, you can build your packages up to 80% faster than with a traditional sequential build process.
*   **Improve Security:** The action automatically verifies the checksums of your release artifacts, so you can be confident that you're building from a secure source.
*   **Reduce Configuration:** With auto-discovery, you don't have to worry about manually configuring the release patterns for each architecture. The action does it for you.
*   **Gain Insight:** The build summary and real-time progress tracking give you a clear view of your build process, so you can quickly identify and resolve any issues.

## Documentation

- **[Quick Start Guide](docs/quick-start-guide.md)** - How to get started
- **[Core Concepts](docs/core-concepts.md)** - Core concepts of the action
- **[Best Practices](docs/best-practices.md)** - Best practices for using the action
- **[Configuration Reference](docs/configuration-reference.md)** - Detailed configuration reference
- **[Performance Tuning](docs/performance-tuning.md)** - Performance tuning and parallel builds
- **[Auto-Discovery](docs/auto-discovery.md)** - How auto-discovery works
- **[Security Guide](docs/security-guide.md)** - Checksum verification
- **[Build Summary](docs/build-summary.md)** - CI/CD integration guide
- **[Lintian Integration](docs/lintian-integration.md)** - Package quality validation with lintian
- **[Project Structure](docs/project-structure.md)** - Codebase organization
- **[Usage Guide](docs/usage-guide.md)** - Detailed usage instructions and examples
- **[Build Monitoring](docs/build-monitoring.md)** - Build output, progress tracking, and monitoring
- **[Migration Guide](docs/migration-guide.md)** - Migrating from single-arch to multi-arch builds
- **[Troubleshooting Guide](docs/troubleshooting-guide.md)** - Common issues and solutions

## Action Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `config-file` | Path to multiarch config YAML | Yes | - |
| `version` | Version of software to build | Yes | - |
| `build-version` | Debian build version number | Yes | - |
| `architecture` | Architecture to build or "all" | No | `all` |
| `max-parallel` | Maximum concurrent builds (2-4 recommended) | No | `2` |
| `lintian-check` | Enable lintian validation of built packages | No | `false` |

For more details on the `max-parallel` setting, see the **[Configuration Reference](docs/configuration-reference.md#max-parallel-configuration)**.

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Reporting issues
- Submitting changes
- Development workflow
- Testing requirements

## License

MIT License - See LICENSE file for details

## Credits

Created by [@ranjithrajv](https://github.com/ranjithrajv)

Based on the multi-architecture work in [uv-debian](https://github.com/dariogriffo/uv-debian)

For use with packages hosted at [debian.griffo.io](https://debian.griffo.io) by [@dariogriffo](https://github.com/dariogriffo)

## Support

- Report issues: [GitHub Issues](https://github.com/ranjithrajv/debian-multiarch-builder/issues)
- Discussions: [GitHub Discussions](https://github.com/ranjithrajv/debian-multiarch-builder/discussions)
- Documentation: Check [docs/](docs/) directory for detailed guides
- Changelog: See [CHANGELOG.md](CHANGELOG.md) for release history
