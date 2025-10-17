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

## Development Guidelines

### Code Style

- Use consistent indentation (2 spaces for YAML, appropriate for shell scripts)
- Add comments for complex logic
- Follow existing naming conventions

### Testing

- Test changes with at least one example configuration
- Verify builds complete successfully
- Check error handling works as expected

### Documentation

- Update README.md for user-facing changes
- Update relevant docs in `docs/` directory
- Add examples for new features
- Update CHANGELOG.md following [Keep a Changelog](https://keepachangelog.com/) format

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
debian-multiarch-builder/
├── .github/
│   └── workflows/        # GitHub Actions workflows
├── docs/                 # Detailed documentation
│   ├── MIGRATION.md
│   ├── USAGE.md
│   └── TROUBLESHOOTING.md
├── examples/             # Configuration examples
├── build.sh              # Main build script
├── Dockerfile            # Package build template
├── action.yml            # GitHub Action definition
├── README.md             # Main documentation
├── CHANGELOG.md          # Version history
└── CONTRIBUTING.md       # This file
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
