# Enable Docker BuildKit for parallel layer building and better caching
#syntax=docker/dockerfile:1.6

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

# Install necessary tools and cleanup in a single layer
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && apt-get install -y \
    sed \
    gzip \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create directory structure in a single layer
RUN mkdir -p /output/usr/bin \
    && mkdir -p "/output/usr/share/doc/${PACKAGE_NAME}" \
    && mkdir -p /output/DEBIAN

# Copy binaries from the extracted release and set permissions in one layer
COPY ${BINARY_SOURCE}/* /output/usr/bin/
RUN chmod +x /output/usr/bin/*

# Copy package metadata files
COPY output/DEBIAN/control /tmp/control.template
COPY output/copyright /output/usr/share/doc/${PACKAGE_NAME}/
COPY output/changelog.Debian /tmp/changelog.template

# Copy README if it exists (optional)
COPY output/ /tmp/package-files/
RUN if [ -f /tmp/package-files/README.md ]; then \
        cp /tmp/package-files/README.md "/output/usr/share/doc/${PACKAGE_NAME}/"; \
    fi && \
    rm -rf /tmp/package-files/

# Process templates and create final files in a single layer
RUN sed -e "s/PACKAGE_NAME/${PACKAGE_NAME}/g" \
        -e "s/DIST/${DEBIAN_DIST}/g" \
        -e "s/BUILD_VERSION/${BUILD_VERSION}/g" \
        -e "s/VERSION/${VERSION}/g" \
        -e "s/SUPPORTED_ARCHITECTURES/${ARCH}/g" \
        -e "s|GITHUB_REPO|${GITHUB_REPO}|g" \
        /tmp/control.template > /output/DEBIAN/control

RUN sed -e "s/PACKAGE_NAME/${PACKAGE_NAME}/g" \
        -e "s/DIST/${DEBIAN_DIST}/g" \
        -e "s/FULL_VERSION/${FULL_VERSION}/g" \
        -e "s/VERSION/${VERSION}/g" \
        /tmp/changelog.template | gzip -9 > "/output/usr/share/doc/${PACKAGE_NAME}/changelog.Debian.gz"

# Cleanup temporary files
RUN rm -f /tmp/control.template /tmp/changelog.template

# Build the .deb package
RUN dpkg-deb --build /output "/${PACKAGE_NAME}_${FULL_VERSION}.deb"

# Use multi-stage build to keep final image minimal
FROM scratch
ARG PACKAGE_NAME
ARG FULL_VERSION
COPY --from=0 "/${PACKAGE_NAME}_${FULL_VERSION}.deb" /
