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
ARG BINARY_RENAME
ARG BUNDLE
ARG DEPENDS
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

# Copy the extracted release into a staging area, then either (a) keep only
# actual executables in /usr/bin - the default - or (b) for BUNDLE=true
# packages, install the whole tree intact under /usr/lib/<package>/ and
# symlink its bin/ executables into /usr/bin.
#
# (a) Upstream tarballs commonly bundle docs, man pages, and shell
# completions alongside the binary (e.g. ripgrep ships 11 extra files -
# CHANGELOG, man page, 4 shell completions, licenses) and blindly copying
# everything pollutes /usr/bin with non-executable clutter, some of it left
# world-executable.
#
# (b) Some upstreams ship a full install tree instead - e.g.
# zed-industries/zed's zed.app/{bin,lib,libexec,share} - where bin/zed's
# RPATH is $ORIGIN-relative (../lib, ../libexec/zed-editor) and only
# resolves correctly if bin/, lib/, and libexec/ stay siblings on disk.
# Flattening top-level files (case a) would drop lib/libexec entirely and
# leave the binary unable to find its shared libraries. $ORIGIN is resolved
# from the executable's real (symlink-followed) path, so a /usr/bin symlink
# into /usr/lib/<package>/bin/ works correctly here.
# Two COPY forms are needed because Docker treats them differently: the
# glob form (used by the non-bundle branch) merges each matched entry's
# *contents* into the destination independently, flattening away any
# subdirectory name (bin/, lib/, libexec/ would all collapse together) -
# fine for the non-bundle case, which only wants top-level files anyway.
# The non-glob single-directory form instead preserves one level of nested
# structure, which BUNDLE mode needs to keep bin/, lib/, and libexec/
# intact as siblings.
COPY ${BINARY_SOURCE}/* /tmp/binary-source/
COPY ${BINARY_SOURCE} /tmp/binary-bundle
RUN if [ "$BUNDLE" = "true" ]; then \
        rm -rf /tmp/binary-source \
        && mkdir -p "/output/usr/lib/${PACKAGE_NAME}" \
        && cp -a /tmp/binary-bundle/. "/output/usr/lib/${PACKAGE_NAME}/" \
        && rm -rf /tmp/binary-bundle \
        && if [ -d "/output/usr/lib/${PACKAGE_NAME}/bin" ]; then \
               for f in "/output/usr/lib/${PACKAGE_NAME}/bin/"*; do \
                   [ -f "$f" ] || continue; \
                   file -b "$f" | grep -q "^ELF " || continue; \
                   chmod +x "$f"; \
                   ln -s "/usr/lib/${PACKAGE_NAME}/bin/$(basename "$f")" "/output/usr/bin/$(basename "$f")"; \
               done; \
           fi; \
    else \
        rm -rf /tmp/binary-bundle; \
        for f in /tmp/binary-source/*; do \
            [ -f "$f" ] || continue; \
            file -b "$f" | grep -q "^ELF " && cp "$f" /output/usr/bin/ || true; \
        done \
        && chmod +x /output/usr/bin/* \
        && rm -rf /tmp/binary-source; \
    fi \
    && [ -n "$(ls -A /output/usr/bin 2>/dev/null)" ] || \
       (echo "ERROR: no executables landed in /usr/bin (BUNDLE=$BUNDLE, BINARY_SOURCE=$BINARY_SOURCE) - check binary_path/bundle config" >&2; exit 1)

# Some upstreams embed the OS/arch suffix directly in the binary's own
# filename inside the release archive (e.g. mikefarah/yq ships
# "yq_linux_amd64", "yq_linux_loong64", etc. rather than a plain "yq"),
# which would otherwise install an executable users can't guess the name
# of. When binary_rename is set in package.yaml and exactly one
# executable was found, rename it to the expected command name.
RUN if [ -n "$BINARY_RENAME" ]; then \
        count=$(find /output/usr/bin -maxdepth 1 -type f | wc -l); \
        if [ "$count" = "1" ]; then \
            f=$(find /output/usr/bin -maxdepth 1 -type f); \
            mv "$f" "/output/usr/bin/$BINARY_RENAME"; \
        else \
            echo "WARNING: binary_rename set but found $count executables in /usr/bin, skipping rename" >&2; \
        fi \
    fi

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

# Some upstream binaries dynamically link against a shared library that
# isn't installed by default on a bare Debian system (e.g. pnpm's Node
# single-executable-application binary needs libatomic1, which a minimal
# install doesn't pull in on its own) - apt won't install it automatically
# unless the package declares it. When depends is set in package.yaml,
# append a Depends: line so apt installs it alongside the package.
RUN if [ -n "$DEPENDS" ]; then \
        echo "Depends: ${DEPENDS}" >> /output/DEBIAN/control; \
    fi

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
