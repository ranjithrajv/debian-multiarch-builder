# Migration Guide

## From Single-Arch Build

If you have an existing single-architecture build setup:

1. **Create config file** - Add `multiarch-config.yaml` with your current architecture
2. **Update workflow** - Replace custom build step with this action
3. **Add more architectures** - Add additional architecture mappings as needed
4. **Update control files** - Replace hardcoded values with placeholders

## Minimal Changes Required

For each package repository, you only need to:
1. Add `multiarch-config.yaml` (new file)
2. Update `.github/workflows/release.yml` (modify existing)
3. Update `output/DEBIAN/control` (add placeholders)

Your `Dockerfile` and `build.sh` can be removed - the action provides these.

## Advantages

- **Centralized Maintenance**: Update build logic in one place, benefits all packages
- **Consistency**: All packages use the same build process
- **Easy Updates**: Add new architectures globally without touching individual repos
- **Reduced Duplication**: No need to copy/paste build scripts across repos
- **Version Control**: Pin action to specific version for stability
- **Testing**: Test changes in action repo before deploying to production
