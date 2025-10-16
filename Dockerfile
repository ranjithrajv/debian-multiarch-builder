ARG DEBIAN_DIST=bookworm
FROM debian:${DEBIAN_DIST}

ARG DEBIAN_DIST
ARG PACKAGE_NAME
ARG VERSION
ARG BUILD_VERSION
ARG FULL_VERSION
ARG ARCH
ARG BINARY_SOURCE
ARG GITHUB_REPO

# Install necessary tools
RUN apt-get update && apt-get install -y \
    sed \
    gzip \
    && rm -rf /var/lib/apt/lists/*

# Create directory structure
RUN mkdir -p /output/usr/bin
RUN mkdir -p /output/usr/share/doc/${PACKAGE_NAME}
RUN mkdir -p /output/DEBIAN

# Copy binaries from the extracted release
COPY ${BINARY_SOURCE}/* /output/usr/bin/

# Ensure binaries are executable
RUN chmod +x /output/usr/bin/*

# Copy package metadata files
COPY output/DEBIAN/control /output/DEBIAN/
COPY output/copyright /output/usr/share/doc/${PACKAGE_NAME}/
COPY output/changelog.Debian /output/usr/share/doc/${PACKAGE_NAME}/

# Copy README if it exists (optional)
COPY output/README.md /output/usr/share/doc/${PACKAGE_NAME}/ 2>/dev/null || true

# Compress changelog
RUN gzip -9 /output/usr/share/doc/${PACKAGE_NAME}/changelog.Debian

# Replace placeholders in control file
RUN sed -i "s/PACKAGE_NAME/${PACKAGE_NAME}/g" /output/DEBIAN/control
RUN sed -i "s/DIST/${DEBIAN_DIST}/g" /output/DEBIAN/control
RUN sed -i "s/VERSION/${VERSION}/g" /output/DEBIAN/control
RUN sed -i "s/BUILD_VERSION/${BUILD_VERSION}/g" /output/DEBIAN/control
RUN sed -i "s/SUPPORTED_ARCHITECTURES/${ARCH}/g" /output/DEBIAN/control
RUN sed -i "s|GITHUB_REPO|${GITHUB_REPO}|g" /output/DEBIAN/control

# Replace placeholders in changelog
RUN sed -i "s/PACKAGE_NAME/${PACKAGE_NAME}/g" /output/usr/share/doc/${PACKAGE_NAME}/changelog.Debian.gz
RUN sed -i "s/DIST/${DEBIAN_DIST}/g" /output/usr/share/doc/${PACKAGE_NAME}/changelog.Debian.gz
RUN sed -i "s/FULL_VERSION/${FULL_VERSION}/g" /output/usr/share/doc/${PACKAGE_NAME}/changelog.Debian.gz
RUN sed -i "s/VERSION/${VERSION}/g" /output/usr/share/doc/${PACKAGE_NAME}/changelog.Debian.gz

# Build the .deb package
RUN dpkg-deb --build /output /${PACKAGE_NAME}_${FULL_VERSION}.deb
