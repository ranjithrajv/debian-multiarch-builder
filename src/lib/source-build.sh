#!/bin/bash

# Source-mode builds.
#
# Opt-in via `build_mode: source` in package.yaml. For upstreams that publish
# no Linux binaries there is no release asset to repack, so this path fetches
# the upstream source tag, compiles it inside debian:<suite>, stages the
# install tree, computes runtime Depends with dpkg-shlibdeps, and wraps the
# result with dpkg-deb.
#
# This generalizes the pilot in latest-debs/quickshell-debian
# (.github/scripts/build-source.sh); packages that opt in are built on native
# runners only (no QEMU/cross), one container per suite/arch cell.

# True when the current package opted into a source build.
source_build_enabled() {
    [ "${BUILD_MODE:-binary}" = "source" ]
}

# Suites to build: explicit build_suites (minus skip_suites) when set,
# otherwise the package's resolved DISTRIBUTIONS.
source_build_suites() {
    local suites="${BUILD_SUITES:-}"
    [ -n "$suites" ] || suites="$DISTRIBUTIONS"

    local out="" suite skip
    for suite in $suites; do
        skip=false
        for s in ${SKIP_SUITES:-}; do
            [ "$suite" = "$s" ] && skip=true && break
        done
        [ "$skip" = "true" ] && continue
        out="$out $suite"
    done
    printf '%s' "${out# }"
}

# Architectures for a source build come from the config's `architectures:`
# (source mode has no release assets to auto-discover, so the release-asset
# architecture filter used by the binary path does not apply).
source_build_architectures() {
    get_supported_architectures
}

# Build one suite/arch cell and leave the .deb in the current directory.
# Returns non-zero on any failure so the caller can keep going with other
# cells rather than aborting the whole run.
build_source_distribution() {
    local build_arch="$1" dist="$2"

    if ! command -v docker >/dev/null 2>&1; then
        error "docker is required for build_mode: source" "docker_missing"
    fi

    # Debian policy requires the Version field to start with a digit; strip
    # any non-digit prefix from the upstream tag (v0.3.1 -> 0.3.1).
    local debian_version
    debian_version=$(echo "$VERSION" | sed -E 's/^[^0-9]*//')
    local full_version="${debian_version}-${BUILD_VERSION}+${dist}_${build_arch}"
    local deb="${PACKAGE_NAME}_${full_version}.deb"

    # The ref to fetch: explicit upstream_ref wins, else the raw version tag.
    local ref="${UPSTREAM_REF:-$VERSION}"

    # Cache the source tarball on the host (defaults to the template's
    # /tmp/download_cache) so re-runs and the other suites reuse one download
    # instead of curling inside every container.
    local dl_cache="${DOWNLOAD_CACHE_DIR:-/tmp/download_cache}"
    mkdir -p "$dl_cache"
    local safe_ref="${ref//\//_}"
    local tarball="${PACKAGE_NAME}-${safe_ref}.tar.gz"
    local src_url
    if [ -n "${UPSTREAM_URL:-}" ]; then
        src_url="${UPSTREAM_URL%/}/archive/${ref}.tar.gz"
    else
        src_url="https://github.com/${GITHUB_REPO}/archive/refs/tags/${ref}.tar.gz"
    fi
    if [ -s "$dl_cache/$tarball" ]; then
        info "Using cached source tarball: $tarball"
    else
        info "Downloading source: $src_url"
        if ! curl -fsSL "$src_url" -o "$dl_cache/$tarball.tmp"; then
            warning "Failed to download source from $src_url"
            rm -f "$dl_cache/$tarball.tmp"
            return 1
        fi
        mv "$dl_cache/$tarball.tmp" "$dl_cache/$tarball"
    fi

    # Per-suite apt archive cache. Lives under the same /tmp/download_cache
    # the scaffold already restores/saves, so it needs no extra workflow step,
    # and is user-writable (unlike /var/cache/apt/archives). A separate dir per
    # suite keeps Debian suites from mixing .debs.
    local apt_cache_root="${SOURCE_APT_ARCHIVE_CACHE_DIR:-$dl_cache/apt}"
    local apt_cache="$apt_cache_root/$dist"
    mkdir -p "$apt_cache"

    local base_image
    base_image="$(base_image_for_dist "$dist")"

    local lintian="${LINTIAN_CHECK:-false}"

    # Optional per-suite apt override. build_depends_suites.<suite> names a
    # source suite (from) and packages to install from it with `apt-get
    # install -t <from>`; build_apt_sources.<from> supplies that suite's
    # repository lines. Used when a base suite is too old for a build dep -
    # e.g. quickshell's trixie build needs forky's wayland-protocols
    # (ext-background-effect-v1). All absent -> no change.
    local override_from override_pkgs extra_sources
    override_from="$(yq eval ".build_depends_suites.\"$dist\".from // \"\"" "$CONFIG_FILE" 2>/dev/null || true)"
    if [ "$override_from" = "null" ] || [ -z "$override_from" ]; then
        override_from=""
    fi
    override_pkgs="$(yq eval "((.build_depends_suites.\"$dist\".packages // []) | join(\" \"))" "$CONFIG_FILE" 2>/dev/null || true)"
    if [ "$override_pkgs" = "null" ]; then
        override_pkgs=""
    fi
    extra_sources=""
    if [ -n "$override_from" ]; then
        extra_sources="$(yq eval "(.build_apt_sources.\"$override_from\" // []) | .[]" "$CONFIG_FILE" 2>/dev/null || true)"
    fi

    local docker_log="/tmp/source-build-${dist}-${build_arch}.log"
    info "Compiling $PACKAGE_NAME $ref in $base_image ($build_arch)..."

    docker run --rm \
        -e LINTIAN="$lintian" \
        -v "$PWD:/out" \
        -v "$dl_cache:/cache:ro" \
        -v "$apt_cache:/var/cache/apt/archives" \
        -w /build \
        "$base_image" bash -c '
        set -euo pipefail
        PACKAGE_NAME="$1"; FULL_VERSION="$2"; DEB="$3"; ARCH="$4"; SUITE="$5"
        REF="$6"; UPSTREAM_URL="$7"; GITHUB_REPO="$8"; BUILD_DEPS="$9"
        CMAKE_FLAGS="${10}"; MAINTAINER="${11}"; DESCRIPTION="${12}"; LINTIAN="${13}"
        EXTRA_SOURCES="${14}"; OVERRIDE_FROM="${15}"; OVERRIDE_PKGS="${16}"; TARBALL="${17}"

        export DEBIAN_FRONTEND=noninteractive
        if [ -n "$EXTRA_SOURCES" ]; then
            printf "%s\n" "$EXTRA_SOURCES" > /etc/apt/sources.list.d/source-build-extra.list
        fi
        apt-get update -qq
        # Toolchain is always installed; build_depends adds upstream-specific
        # -dev packages on top.
        apt-get install -y -qq \
            build-essential cmake ninja-build pkg-config file \
            curl ca-certificates dpkg-dev $BUILD_DEPS >/dev/null
        # Per-suite pins: install these from OVERRIDE_FROM (its repository was
        # added above), e.g. the forky wayland-protocols on trixie.
        if [ -n "$OVERRIDE_FROM" ] && [ -n "$OVERRIDE_PKGS" ]; then
            apt-get install -y -qq -t "$OVERRIDE_FROM" $OVERRIDE_PKGS >/dev/null
        fi

        mkdir -p /src /build /stage/DEBIAN
        if [ ! -s "/cache/$TARBALL" ]; then
            echo "ERROR: cached source tarball /cache/$TARBALL missing" >&2
            exit 1
        fi
        echo "::group::extract /cache/$TARBALL"
        tar -xf "/cache/$TARBALL" -C /src --strip-components=1
        echo "::endgroup::"

        cmake -S /src -B /build -G Ninja \
            -DCMAKE_INSTALL_PREFIX=/usr $CMAKE_FLAGS
        cmake --build /build
        DESTDIR=/stage cmake --install /build

        # Runtime Depends from every ELF we ship.
        mkdir -p /build/debian
        cat > /build/debian/control <<CTRL
Source: ${PACKAGE_NAME}
Section: utils
Priority: optional
Maintainer: ${MAINTAINER}
Standards-Version: 4.7.0

Package: ${PACKAGE_NAME}
Architecture: any
Depends: \${shlibs:Depends}
Description: ${DESCRIPTION}
CTRL

        mapfile -t elfs < <(find /stage -type f \
            -exec sh -c '"'"'file -b "$1" | grep -q "^ELF" && echo "$1"'"'"' _ {} \; 2>/dev/null)
        depends=""
        if [ "${#elfs[@]}" -gt 0 ]; then
            depends="$(cd /build && dpkg-shlibdeps -O "${elfs[@]}" 2>/dev/null \
                | sed -n "s/^shlibs:Depends=//p" || true)"
        fi
        [ -n "$depends" ] || depends="libc6"

        mkdir -p "/stage/usr/share/doc/${PACKAGE_NAME}"
        cat > "/stage/usr/share/doc/${PACKAGE_NAME}/changelog.Debian" <<CLOG
${PACKAGE_NAME} (${FULL_VERSION}) unstable; urgency=medium

  * Built from upstream source ${REF}.

 -- ${MAINTAINER}  $(date -R)
CLOG
        gzip -9 -f "/stage/usr/share/doc/${PACKAGE_NAME}/changelog.Debian"

        cat > /stage/DEBIAN/control <<CTRL
Package: ${PACKAGE_NAME}
Version: ${FULL_VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: ${depends}
Maintainer: ${MAINTAINER}
Description: ${DESCRIPTION}
CTRL

        dpkg-deb -b /stage "/out/${DEB}"

        if [ "$LINTIAN" = "true" ]; then
            apt-get install -y -qq lintian >/dev/null 2>&1 || true
            lintian --no-tag-display-limit "/out/${DEB}" \
                || echo "::warning::lintian reported findings for ${DEB}"
        fi
    ' _ \
        "$PACKAGE_NAME" "$full_version" "$deb" "$build_arch" "$dist" \
        "$ref" "${UPSTREAM_URL:-}" "${GITHUB_REPO:-}" "${BUILD_DEPENDS:-}" \
        "${CMAKE_FLAGS:-}" "$PACKAGE_MAINTAINER" "$PACKAGE_DESCRIPTION" \
        "$lintian" "${extra_sources:-}" "${override_from:-}" "${override_pkgs:-}" \
        "$tarball" \
        2>&1 | tee "$docker_log"
    local rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ]; then
        mkdir -p failed-build-logs
        mv -f "$docker_log" "failed-build-logs/source-${dist}-${build_arch}.log" 2>/dev/null || true
        return 1
    fi

    rm -f "$docker_log"
    if [ ! -s "./$deb" ]; then
        warning "Source build produced no package: $deb"
        return 1
    fi
    success "Built $deb"
    return 0
}

# Entry point for build_mode: source. Replaces the binary orchestration in
# main.sh; builds every configured suite/arch cell, then emits the Debian
# source (.dsc) package so apt-get source works, mirroring the binary path.
run_source_build() {
    if [ "$BUILD_SYSTEM" != "cmake" ]; then
        error "build_mode: source currently supports build_system: cmake only (got '$BUILD_SYSTEM')" "config_invalid"
    fi

    local arches
    arches="$(source_build_architectures)"
    # Source mode has nothing to auto-discover, so the default-arch fallback
    # must not silently kick in: require an explicit architectures: list.
    if [ "${AUTO_DISCOVERY:-false}" = "true" ] || [ -z "$arches" ]; then
        error "build_mode: source requires an explicit architectures: list in package.yaml" "config_invalid"
    fi

    local suites
    suites="$(source_build_suites)"
    if [ -z "$suites" ]; then
        error "No suites to build (build_suites/distributions resolved empty)" "config_invalid"
    fi

    info "Source build: $PACKAGE_NAME $VERSION-$BUILD_VERSION"
    info "Suites: $suites"
    info "Architectures: $(echo "$arches" | tr '\n' ' ')"

    local built=0 failed=0 arch suite
    for arch in $arches; do
        for suite in $suites; do
            if build_source_distribution "$arch" "$suite"; then
                built=$((built + 1))
            else
                failed=$((failed + 1))
                warning "Source build failed for $suite/$arch"
            fi
        done
    done

    if [ "$built" -eq 0 ]; then
        error "No packages were built from source" "source_build_failed"
    fi
    [ "$failed" -eq 0 ] || warning "$failed source build cell(s) failed"

    ls -lh ${PACKAGE_NAME}_*.deb 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || true

    # Emit .dsc source packages from the built binaries, same as the binary
    # path (best-effort; the .debs stand on their own if this fails).
    if ! command -v build_source_packages >/dev/null 2>&1; then
        source "$SCRIPT_DIR/lib/source-package.sh"
    fi
    build_source_packages

    return 0
}
