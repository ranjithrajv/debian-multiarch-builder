# Best Practices

This document provides best practices for using the Debian Multi-Architecture Package Builder.

## Configuration

*   **Use Auto-Discovery:** Whenever possible, use the auto-discovery feature to simplify your configuration. This will make your workflow more resilient to changes in the upstream release process.

*   **Use `overrides.yaml` for Customizations:** Instead of modifying the main `package.yaml` file, use an `overrides.yaml` file to customize the build process. This will make it easier to update the main configuration file in the future.

*   **Specify a `binary_path`:** If the binaries in the release artifact are not in the root directory, specify the `binary_path` in your `package.yaml` file. This will ensure that the action can find the binaries.

## Performance

*   **Adjust `max-parallel`:** The `max-parallel` input controls the number of parallel architecture builds. The optimal value depends on your runner resources:
  - GitHub Actions standard runners: `max-parallel: 2` (2 CPU cores, 7GB RAM)
  - Self-hosted runners with 4+ cores: `max-parallel: 4`
  - High-performance runners: `max-parallel: 6-8` (monitor resource usage)
  
   For detailed performance optimization information, see **[Performance Tuning](performance-tuning.md)** and **[CHANGELOG](../CHANGELOG.md)**.

# Cache Management:
  - **Download Cache**
  - **API Cache**
  - **Docker Cache**
*   **Verify Checksums:** The action automatically verifies the checksums of the downloaded release artifacts. However, you should also manually verify the checksums of the generated `.deb` packages before distributing them.

*   **Use a Specific Version:** Instead of using a floating version like `v1`, use a specific version of the action in your workflow. This will ensure that your workflow is not affected by any breaking changes in the action.
