# Contributing to Debian Multi-Architecture Builder

Thank you for considering contributing to this project! We welcome contributions of all kinds.

## How to Contribute

### Reporting Issues

- Check existing issues before creating a new one
- Provide clear description and reproduction steps
- Include relevant configuration files (sanitized)
- Specify your environment (OS, Docker version, etc.)
- For auto-discovery issues, include the GitHub repo and version tested

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
   - Test auto-discovery mode: `./build.sh --ad owner/repo version 1`
   - Test setup wizard: `./build.sh --setup`
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
*   [jq](https://stedolan.github.io/jq/) - For JSON processing

### Running Tests

The action does not have a formal test suite. However, you can test your changes by:

1. **Testing with config files:**
   ```bash
   ./build.sh examples/lazygit-config.yaml 0.38.2 1 all
   ```

2. **Testing auto-discovery mode:**
   ```bash
   ./build.sh --ad eza-community/eza v0.23.4 1
   ```

3. **Testing dry-run validation:**
   ```bash
   ./build.sh templates/rust/eza.yaml v0.23.4 1 --dry-run
   ```

4. **Testing error handling:**
   ```bash
   ./build.sh nonexistent.yaml v1.0.0 1
   ```

### Building the Action

The action is a composite action, so there is no need to build it. You can simply use the action directly from the repository.

## Adding New Features

### Auto-Discovery Support

When adding auto-discovery support for new project types:
1. Update `src/lib/zero-config.sh` pattern detection
2. Add test cases with real GitHub repositories
3. Document supported patterns in `docs/auto-discovery.md`
4. Add to CHANGELOG.md

### Template Contributions

When adding new templates:
1. Create template in `templates/{language}/project.yaml`
2. Add entry to `templates/README.md`
3. Test with actual releases from the project
4. Document any special considerations

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
4. Document in README.md and docs/

## Project Structure

```
src/
├── lib/
│   ├── logging.sh          # Logging and output formatting
│   ├── config.sh           # Configuration parsing and validation
│   ├── config-simple.sh    # Simplified configuration
│   ├── github-api.sh       # GitHub API interactions
│   ├── discovery.sh        # Architecture pattern discovery
│   ├── validation.sh       # Release and checksum validation
│   ├── build.sh            # Core build functions
│   ├── orchestration.sh    # Build orchestration (parallel and sequential)
│   ├── progress.sh         # Progress visualization
│   ├── summary.sh          # Build summary generation
│   ├── dry-run.sh          # Dry-run validation
│   └── zero-config.sh      # Auto-discovery mode and setup wizard
├── data/
│   ├── system.yaml         # System constants and Debian official policies
│   └── defaults.yaml       # User-configurable default settings
├── main.sh                 # Main entry point
build.sh                    # Wrapper for backward compatibility
templates/                  # Pre-built configuration templates
.github/workflows/          # Demo and example workflows
docs/                       # Documentation
examples/                   # Example configurations
```

## Code Style

- Use descriptive variable names
- Add comments for complex logic
- Follow shell best practices (quote variables, check exit codes)
- Use functions for reusable code
- Keep functions under 50 lines when possible
- Use `local` for function-scoped variables

## Documentation

When contributing documentation:
1. Use clear, concise language
2. Include examples for all features
3. Add troubleshooting sections for common issues
4. Keep formatting consistent with existing docs
5. Update table of contents if adding new pages

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
