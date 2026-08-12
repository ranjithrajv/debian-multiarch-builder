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
ARG DESCRIPTION
ARG LICENSE_SPDX
ARG LICENSE_TEXT

# Install necessary tools and cleanup in a single layer
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
    file \
    gettext-base \
    gzip \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Expose ARG values as ENV for envsubst (handles naming mismatches)
ENV DIST=${DEBIAN_DIST} \
    SUPPORTED_ARCHITECTURES=${ARCH}

# Create directory structure in a single layer
RUN mkdir -p /output/usr/bin \
    && mkdir -p "/output/usr/share/doc/${PACKAGE_NAME}" \
    && mkdir -p /output/DEBIAN

# Copy the extracted release into a staging area, then keep only actual
# executables in /usr/bin. Upstream tarballs commonly bundle docs, man
# pages, and shell completions alongside the binary (e.g. ripgrep ships
# 11 extra files - CHANGELOG, man page, 4 shell completions, licenses)
# and blindly copying everything pollutes /usr/bin with non-executable
# clutter, some of it left world-executable.
COPY ${BINARY_SOURCE}/* /tmp/binary-source/
RUN for f in /tmp/binary-source/*; do \
        [ -f "$f" ] || continue; \
        file -b "$f" | grep -q "^ELF " && cp "$f" /output/usr/bin/; \
    done \
    && chmod +x /output/usr/bin/* \
    && rm -rf /tmp/binary-source

# Copy package metadata files
COPY output/DEBIAN/control /tmp/control.template
COPY output/copyright /tmp/copyright.template
COPY output/changelog.Debian /tmp/changelog.template

# Copy README if it exists (optional)
COPY output/ /tmp/package-files/
RUN if [ -f /tmp/package-files/README.md ]; then \
        cp /tmp/package-files/README.md "/output/usr/share/doc/${PACKAGE_NAME}/"; \
    fi && \
    rm -rf /tmp/package-files/

# Process templates and create final files in a single layer
RUN envsubst '${PACKAGE_NAME} ${VERSION} ${BUILD_VERSION} ${DIST} ${SUPPORTED_ARCHITECTURES} ${GITHUB_REPO} ${DESCRIPTION}' \
        < /tmp/control.template > /output/DEBIAN/control

RUN envsubst '${PACKAGE_NAME} ${FULL_VERSION} ${DIST} ${VERSION}' \
        < /tmp/changelog.template | gzip -9 > "/output/usr/share/doc/${PACKAGE_NAME}/changelog.Debian.gz"

RUN YEAR=$(date +%Y) envsubst '${PACKAGE_NAME} ${GITHUB_REPO} ${YEAR} ${LICENSE_SPDX} ${LICENSE_TEXT}' \
        < /tmp/copyright.template > "/output/usr/share/doc/${PACKAGE_NAME}/copyright"

# Cleanup temporary files
RUN rm -f /tmp/control.template /tmp/changelog.template /tmp/copyright.template

# Build the .deb package
RUN dpkg-deb --build /output "/${PACKAGE_NAME}_${FULL_VERSION}.deb"

# Use multi-stage build to keep final image minimal
FROM scratch
ARG PACKAGE_NAME
ARG FULL_VERSION
COPY --from=0 "/${PACKAGE_NAME}_${FULL_VERSION}.deb" /
