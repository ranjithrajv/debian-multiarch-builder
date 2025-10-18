# Debian Multi-Architecture Package Builder

A reusable GitHub Action for building Debian packages across multiple architectures from upstream releases. This action simplifies the process of creating multi-architecture Debian packages for projects distributed via GitHub releases.

## Features

- Build Debian packages for multiple architectures and distributions
- **Multi-level parallelization** for faster builds
- **Download caching** to reduce build time
- **Checksum verification** for improved security
- **Auto-discovery** of release artifacts
- **Build summary JSON** for CI/CD integration
- **Real-time progress tracking** and **enhanced observability**

For more details, see the **[Core Concepts](docs/concepts.md)** documentation.

## Documentation

- **[Quick Start Guide](docs/quick-start-guide.md)** - How to get started
- **[Core Concepts](docs/core-concepts.md)** - Core concepts of the action
- **[Best Practices](docs/best-practices.md)** - Best practices for using the action
- **[Configuration Reference](docs/configuration-reference.md)** - Detailed configuration reference
- **[Performance Tuning](docs/performance-tuning.md)** - Performance tuning and parallel builds
- **[Auto-Discovery](docs/auto-discovery.md)** - How auto-discovery works
- **[Security Guide](docs/security-guide.md)** - Checksum verification
- **[Build Summary](docs/build-summary.md)** - CI/CD integration guide
- **[Project Structure](docs/project-structure.md)** - Codebase organization
- **[Usage Guide](docs/usage-guide.md)** - Detailed usage instructions and examples
- **[Build Monitoring](docs/build-monitoring.md)** - Build output, progress tracking, and monitoring
- **[Migration Guide](docs/migration-guide.md)** - Migrating from single-arch to multi-arch builds
- **[Troubleshooting Guide](docs/troubleshooting-guide.md)** - Common issues and solutions

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
