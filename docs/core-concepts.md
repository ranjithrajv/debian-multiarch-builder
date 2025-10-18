# Core Concepts

This document explains the core concepts behind the Debian Multi-Architecture Package Builder.

## Docker-Based Builds

The action uses Docker to ensure a reproducible and consistent build environment. Here's how it works:

1.  **Dynamic Dockerfile:** The action uses a template `Dockerfile` located in `src/Dockerfile`. This `Dockerfile` is dynamically populated with build arguments, such as the Debian distribution, package name, and version.

2.  **Image Build:** For each distribution and architecture, a new Docker image is built using the dynamically generated `Dockerfile`. This image contains all the necessary tools and dependencies to build the Debian package.

3.  **Package Build:** The actual package build happens inside the Docker container. The action copies the source code and the `output` directory into the container and then runs the `dpkg-deb` command to create the `.deb` package.

4.  **Artifact Extraction:** Once the package is built, it's copied from the Docker container to the host machine.

This approach ensures that the build process is isolated from the host environment and that the resulting package is consistent across different machines.

## Multi-Level Parallelization

The action implements two levels of parallelization to significantly speed up the build process:

1.  **Parallel Architecture Builds:** The action can build for multiple architectures concurrently. The number of parallel builds is controlled by the `max-parallel` input.

2.  **Parallel Distribution Builds:** Within each architecture build, the action builds for all specified Debian distributions in parallel.

Here's a visual representation of the parallel execution:

```
+----------------------------------------------------+
| Build for amd64                                    |
| +------------------+ +------------------+ +------------------+ |
| | Build for        | | Build for        | | Build for        | |
| | bookworm         | | trixie           | | sid              | |
| +------------------+ +------------------+ +------------------+ |
+----------------------------------------------------+

+----------------------------------------------------+
| Build for arm64                                    |
| +------------------+ +------------------+ +------------------+ |
| | Build for        | | Build for        | | Build for        | |
| | bookworm         | | trixie           | | sid              | |
| +------------------+ +------------------+ +------------------+ |
+----------------------------------------------------+
```

This multi-level parallelization can reduce the build time by up to 80% compared to a sequential build.

## Auto-Discovery

The auto-discovery feature simplifies the configuration process by automatically finding the correct release artifact for each architecture. Here's how it works:

1.  **Fetch Release Assets:** The action uses the GitHub API to fetch the list of assets for the specified release.

2.  **Pattern Matching:** It then matches the asset names against a list of predefined patterns for each architecture. For example, for the `amd64` architecture, it looks for assets containing `x86_64`, `amd64`, or `x64`.

3.  **Build Preference:** The action has a preference for `gnu` builds over `musl` builds, as `gnu` is the native C library for Debian. If both are available, it will choose the `gnu` build.

4.  **Checksum Verification:** The action also looks for checksum files in the release assets. If a checksum file is found, it's used to verify the integrity of the downloaded artifact.

This feature eliminates the need to manually specify the `release_pattern` for each architecture, making the configuration much simpler.
