ARG DEBIAN_DIST=bookworm
# Base image is derived: Debian suites build FROM debian:<suite>; Ubuntu
# suites (jammy, noble, ...) build FROM ubuntu:<suite>. build_distribution()
# passes BASE_IMAGE explicitly; the default keeps standalone Dockerfile
# builds (docker build --build-arg DEBIAN_DIST=...) working unchanged.
ARG BASE_IMAGE=debian:${DEBIAN_DIST}
FROM ${BASE_IMAGE}

ARG DEBIAN_DIST
ARG PACKAGE_NAME
ARG VERSION
ARG BUILD_VERSION
ARG FULL_VERSION
ARG ARCH
ARG BINARY_SOURCE
ARG GITHUB_REPO
ARG MAINTAINER

# Install necessary tools
RUN apt-get update && apt-get install -y \
    gettext-base \
    gzip \
    && rm -rf /var/lib/apt/lists/*

# Expose ARG values as ENV for envsubst (handles naming mismatches)
ENV DIST=${DEBIAN_DIST} \
    SUPPORTED_ARCHITECTURES=${ARCH} \
    MAINTAINER=${MAINTAINER}

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
COPY output/ /tmp/package-files/
RUN if [ -f /tmp/package-files/README.md ]; then \
        cp /tmp/package-files/README.md /output/usr/share/doc/${PACKAGE_NAME}/; \
    fi

# Process changelog (substitute placeholders, then compress)
RUN envsubst '${PACKAGE_NAME} ${FULL_VERSION} ${DIST} ${VERSION} ${MAINTAINER}' \
        < /output/usr/share/doc/${PACKAGE_NAME}/changelog.Debian | \
        gzip -9 > /output/usr/share/doc/${PACKAGE_NAME}/changelog.Debian.gz && \
        rm /output/usr/share/doc/${PACKAGE_NAME}/changelog.Debian

# Process control file
RUN envsubst '${PACKAGE_NAME} ${VERSION} ${BUILD_VERSION} ${DIST} ${SUPPORTED_ARCHITECTURES} ${GITHUB_REPO} ${MAINTAINER}' \
        < /output/DEBIAN/control > /output/DEBIAN/control.tmp && \
        mv /output/DEBIAN/control.tmp /output/DEBIAN/control

# Build the .deb package
RUN dpkg-deb --build /output /${PACKAGE_NAME}_${FULL_VERSION}.deb
