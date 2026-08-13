#!/bin/bash

# Debian source package (.dsc) generation
#
# Produces a 3.0 (quilt) source package for each distribution the binary
# .debs were built for, so `apt-get source` and the repository's Sources
# index work. Source packages are architecture-independent, so they are
# generated ONCE per distribution on the build host (not inside the per-arch
# Docker builds, which would race on identical filenames). The upstream
# .orig.tar.xz is built once from the reference (amd64, else first) payload
# and shared across distributions.

# Extract the distribution token from a built .deb filename.
# Expects: ${PACKAGE_NAME}_<debian_version>-<build>+<dist>_<arch>.deb
dist_of_deb() {
    local stem="${1%.deb}"
    local rest="${stem%_*}"
    rest="${rest#${PACKAGE_NAME}_}"
    printf '%s' "${rest##*+}"
}

# Generate source packages for every distribution present among the built
# .debs. Best-effort: on any failure the binary builds still stand and this
# logs a warning instead of aborting the run.
build_source_packages() {
    if ! command -v dpkg-source >/dev/null 2>&1; then
        warning "dpkg-source not found; skipping source package generation (install dpkg-dev)"
        return 0
    fi
    if ! command -v dpkg-deb >/dev/null 2>&1; then
        warning "dpkg-deb not found; skipping source package generation"
        return 0
    fi

    # The templates use these placeholders; envsubst reads the environment,
    # so make sure the parsed values are exported even in the sequential /
    # single-architecture paths that skip orchestration.sh.
    export PACKAGE_NAME VERSION BUILD_VERSION GITHUB_REPO PACKAGE_DESCRIPTION
    export LICENSE_SPDX LICENSE_TEXT 2>/dev/null || true

    local debian_version
    debian_version=$(echo "$VERSION" | sed -E 's/^[^0-9]*//')

    # Collect unique distributions from the built .debs.
    local dists=() dist seen
    for f in ${PACKAGE_NAME}_*.deb; do
        [[ -f "$f" ]] || continue
        dist=$(dist_of_deb "$f")
        [[ -n "$dist" ]] || continue
        seen=false
        for d in "${dists[@]:-}"; do
            [[ "$d" == "$dist" ]] && seen=true && break
        done
        [[ "$seen" == "false" ]] && dists+=("$dist")
    done

    if [[ ${#dists[@]} -eq 0 ]]; then
        warning "No built distributions detected; skipping source package generation"
        return 0
    fi

    local src_templates="$SCRIPT_DIR/../templates/source"
    if [[ ! -d "$src_templates" ]]; then
        warning "Source package templates missing at $src_templates; skipping"
        return 0
    fi

    info "Generating Debian source packages for: ${dists[*]}"
    local workdir orig_done
    workdir="$(mktemp -d)"
    orig_done=""

    for dist in "${dists[@]}"; do
        if build_source_package "$dist" "$debian_version" "$workdir" "$src_templates" "$orig_done"; then
            orig_done="yes"
        fi
    done

    rm -rf "$workdir"
    return 0
}

# Build one source package for a single distribution.
build_source_package() {
    local dist="$1" debian_version="$2" workdir="$3" src_templates="$4" orig_done="$5"
    local src_version="${debian_version}-${BUILD_VERSION}+${dist}"
    local tree="${PACKAGE_NAME}-${src_version}"
    local tree_dir="$workdir/$tree"
    local orig_name="${PACKAGE_NAME}_${debian_version}.orig.tar.xz"

    # Reference .deb for the payload: prefer amd64 for this dist, else any.
    local ref_deb="" f
    for f in ${PACKAGE_NAME}_*+${dist}_amd64.deb; do
        [[ -f "$f" ]] && ref_deb="$f" && break
    done
    if [[ -z "$ref_deb" ]]; then
        for f in ${PACKAGE_NAME}_*.deb; do
            [[ -f "$f" ]] || continue
            [[ "$(dist_of_deb "$f")" == "$dist" ]] && ref_deb="$f" && break
        done
    fi
    if [[ -z "$ref_deb" ]]; then
        warning "No .deb for dist $dist; skipping source package"
        return 1
    fi

    mkdir -p "$tree_dir/debian/source"
    if ! dpkg-deb -x "$ref_deb" "$tree_dir"; then
        warning "dpkg-deb -x failed for $ref_deb; skipping source package for $dist"
        return 1
    fi
    rm -rf "$tree_dir/DEBIAN"

    # debian/control
    DESCRIPTION="$PACKAGE_DESCRIPTION" \
    envsubst '${PACKAGE_NAME} ${GITHUB_REPO} ${DESCRIPTION}' \
        < "$src_templates/control" > "$tree_dir/debian/control"

    # debian/rules
    cp "$src_templates/rules" "$tree_dir/debian/rules"
    chmod +x "$tree_dir/debian/rules"

    # debian/changelog
    SRC_VERSION="$src_version" DIST="$dist" VERSION="$debian_version" \
    envsubst '${PACKAGE_NAME} ${SRC_VERSION} ${DIST} ${VERSION}' \
        < "$src_templates/changelog" > "$tree_dir/debian/changelog"

    # debian/copyright (reuse the binary package's copyright template)
    YEAR="$(date +%Y)" \
    envsubst '${PACKAGE_NAME} ${GITHUB_REPO} ${YEAR} ${LICENSE_SPDX} ${LICENSE_TEXT}' \
        < "$SCRIPT_DIR/../templates/output/copyright" > "$tree_dir/debian/copyright"

    # debian/source/format
    printf '3.0 (quilt)\n' > "$tree_dir/debian/source/format"

    # Upstream orig tarball (built once, shared across dists). dpkg-source
    # requires the tarball to contain a top-level <pkg>-<upstream-version>/
    # directory (standard upstream layout), so rewrite the tree dir name
    # uv-0.12.3-1+bookworm -> uv-0.12.3 for the archive.
    if [[ -z "$orig_done" ]]; then
        local upstream_dir="${PACKAGE_NAME}-${debian_version}"
        if ! tar -cJf "$workdir/$orig_name" \
                --transform "s|^$tree|$upstream_dir|" \
                -C "$workdir" "$tree/usr"; then
            warning "Failed to create orig tarball for $dist"
            return 1
        fi
    fi

    # dpkg-source -b writes <pkg>_<src_version>.dsc + .debian.tar.xz into
    # $workdir, using <pkg>_<debian_version>.orig.tar.xz as the upstream tarball.
    if ! ( cd "$workdir" && dpkg-source -b "$tree" >/dev/null 2>&1 ); then
        warning "dpkg-source -b failed for $dist"
        return 1
    fi

    cp "$workdir/${PACKAGE_NAME}_${src_version}.dsc" .
    cp "$workdir/${PACKAGE_NAME}_${src_version}.debian.tar.xz" .
    if [[ -z "$orig_done" ]]; then
        cp "$workdir/$orig_name" .
    fi
    info "  ✓ source package: ${PACKAGE_NAME}_${src_version}.dsc"
    return 0
}