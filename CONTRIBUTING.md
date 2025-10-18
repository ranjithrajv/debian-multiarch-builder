# Contributing to Debian Multi-Architecture Builder

Thank you for considering contributing to this project! We welcome contributions of all kinds.

## How to Contribute

### Reporting Issues

- Check existing issues before creating a new one
- Provide clear description and reproduction steps
- Include relevant configuration files (sanitized)
- Specify your environment (OS, Docker version, etc.)

### Submitting Changes

1. **Fork the repository**
   ```bash
   git clone https://github.com/ranjithrajv/debian-multiarch-builder.git
   cd debian-multiarch-builder
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow existing code style and patterns
   - Add tests if applicable
   - Update documentation as needed

4. **Test your changes**
   - Test with example configurations in `examples/`
   - Verify builds work for multiple architectures
   - Check that documentation is accurate

5. **Commit your changes**
   - Write clear, concise commit messages
   - Follow semantic commit format: `feat:`, `fix:`, `docs:`, `refactor:`, etc.
   - Reference related issues

6. **Submit a pull request**
   - Provide clear description of changes
   - Link related issues
   - Ensure CI checks pass

## Development Workflow

### Local Development Environment

To set up a local development environment, you will need to have the following tools installed:

*   [Docker](https://www.docker.com/)
*   [ShellCheck](https://www.shellcheck.net/)
*   [yq](https://github.com/mikefarah/yq)

### Running Tests

The action does not have a formal test suite. However, you can test your changes by using the example configurations in the `examples/` directory. To do this, you will need to have a local copy of the action. You can then run the action locally using the following command:

```bash
./build.sh examples/lazygit-config.yaml 0.38.2 1 all
```

This will build the `lazygit` package for all supported architectures.

### Building the Action

The action is a composite action, so there is no need to build it. You can simply use the action directly from the repository.

### Submitting Changes

When you are ready to submit your changes, please follow these steps:

1.  **Fork the repository**
2.  **Create a feature branch**
3.  **Make your changes**
4.  **Test your changes**
5.  **Commit your changes**
6.  **Submit a pull request**

## Adding New Features

### Architecture Support

When adding a new architecture:
1. Update `README.md` architecture table
2. Add example in configuration files
3. Document any distribution-specific limitations
4. Update `build.sh` if needed

### Distribution Support

When adding a new Debian distribution:
1. Test with existing architectures
2. Document architecture availability
3. Update examples and documentation
4. Add to CHANGELOG.md

### Configuration Options

When adding new configuration options:
1. Update `multiarch-config.yaml` schema documentation
2. Add validation in `build.sh`
3. Provide examples in `examples/`
4. Document in README.md and docs/USAGE.md

## Project Structure

```
src/
├── lib/
│   ├── utils.sh          # Logging and output formatting
│   ├── config.sh         # Configuration parsing and validation
│   ├── github-api.sh     # GitHub API interactions
│   ├── discovery.sh      # Architecture pattern discovery
│   ├── validation.sh     # Release and checksum validation
│   ├── build.sh          # Core build functions
│   ├── orchestration.sh  # Build orchestration (parallel and sequential)
│   └── summary.sh        # Build summary generation
├── system.yaml           # System constants and Debian official policies
├── defaults.yaml         # User-configurable default settings
├── main.sh               # Main entry point
build.sh                  # Wrapper for backward compatibility
```

## Release Process

Releases are managed by project maintainers:
1. Update CHANGELOG.md with version and date
2. Create git tag with version number
3. Publish to GitHub Marketplace
4. Announce in discussions

## Questions?

- Open a [Discussion](https://github.com/ranjithrajv/debian-multiarch-builder/discussions)
- Check existing [Issues](https://github.com/ranjithrajv/debian-multiarch-builder/issues)
- Review [Documentation](docs/)

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Maintain professional discourse

Thank you for contributing!
