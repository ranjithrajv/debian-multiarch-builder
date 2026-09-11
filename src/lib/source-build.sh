#!/bin/bash

# Source-mode builds.
#
# Opt-in via `build_mode: source` in package.yaml. For upstreams that publish
# no Linux binaries there is no release asset to repack, so this path fetches
# the upstream source tag, compiles it inside debian:<suite>, stages the
# install tree, computes runtime Depends with dpkg-shlibdeps, and wraps the
# result with dpkg-deb.
#
# Compile once per architecture per Debian/Ubuntu family, on that family's
# oldest suite (so the ELF's glibc/Qt symbols are the intersection of every
# suite we ship). Newer suites re-wrap the same tree and re-run shlibdeps
# against that suite's libraries — the same shape as the binary path, which
# downloads one blob per arch and wraps it N times. Packages that opt in are
# built on native runners only (no QEMU/cross).
#
# Per-suite images (toolchain + build_depends + ccache + lld on compile
# images) are baked with docker build; the rootfs is exported to
# download_cache/chroots/ (the warm-run cache). A leftover images/*.tar.gz
# is still loaded if the chroot tarball is missing. Compile cells bind
# download_cache/ccache and drive gcc/g++ through ccache; the linker is
# mold if present, else lld.
#
# Compile stays one job. Wrap images are baked sequentially (so two Qt-sized
# docker builds cannot OOM a runner), then wrap cells run in parallel, capped
# by SOURCE_WRAP_PARALLEL or MAX_PARALLEL.
#
# Compile and wrap run in a Debian chroot (unshare or sudo), not `docker run`.
# Docker only bakes the image and exports the rootfs tarball into
# download_cache/chroots/. A warm run unpacks that tarball and never talks
# to Docker. SOURCE_BUILD_BACKEND=docker|unshare|sudo|auto (default auto).
#
# This generalizes the pilot in latest-debs/quickshell-debian
# (.github/scripts/build-source.sh).

# Oldest → newest. Unknown names are treated as Debian (base_image_for_dist
# already defaults unknown suites to debian:<name>).
SOURCE_BUILD_DEBIAN_ORDER="${SOURCE_BUILD_DEBIAN_ORDER:-bullseye bookworm trixie forky sid}"
SOURCE_BUILD_UBUNTU_ORDER="${SOURCE_BUILD_UBUNTU_ORDER:-jammy noble oracular plucky questing resolute}"
# Bump when the Dockerfile recipe changes so saved images are rebuilt.
SOURCE_BUILD_IMAGE_RECIPE="${SOURCE_BUILD_IMAGE_RECIPE:-3}"

# True when the current package opted into a source build.
source_build_enabled() {
    [ "${BUILD_MODE:-binary}" = "source" ]
}

# True when the suite is an Ubuntu release (native ubuntu:<suite> image).
source_build_is_ubuntu() {
    case "$1" in
        jammy|noble|questing|resolute|plucky|oracular) return 0 ;;
        *) return 1 ;;
    esac
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

source_build_filter_debian() {
    local suites="$1" out="" s
    for s in $suites; do
        source_build_is_ubuntu "$s" && continue
        out="$out $s"
    done
    printf '%s' "${out# }"
}

source_build_filter_ubuntu() {
    local suites="$1" out="" s
    for s in $suites; do
        source_build_is_ubuntu "$s" || continue
        out="$out $s"
    done
    printf '%s' "${out# }"
}

# Oldest suite in $1 according to $2 (space-separated oldest → newest).
# Unrecognized names are ignored until the list is exhausted, then the
# caller's first entry is used so a totally unknown set still compiles.
source_build_oldest_in_order() {
    local suites="$1" order="$2" s t
    for s in $order; do
        for t in $suites; do
            [ "$t" = "$s" ] && { printf '%s' "$s"; return 0; }
        done
    done
    printf '%s' "${suites%% *}"
}

# Oldest suite in a same-family list (Debian *or* Ubuntu, not mixed).
source_build_oldest_suite() {
    local suites="$1"
    [ -n "$suites" ] || return 1
    local first="${suites%% *}"
    if source_build_is_ubuntu "$first"; then
        source_build_oldest_in_order "$suites" "$SOURCE_BUILD_UBUNTU_ORDER"
    else
        source_build_oldest_in_order "$suites" "$SOURCE_BUILD_DEBIAN_ORDER"
    fi
}

# Suites that re-wrap the compiled tree (everything except the compile suite).
source_build_wrap_suites() {
    local suites="$1" compile_suite="$2" out="" s
    for s in $suites; do
        [ "$s" = "$compile_suite" ] && continue
        out="$out $s"
    done
    printf '%s' "${out# }"
}

# True when wrap_list has two or more suites (contains a space).
source_build_wrap_is_parallel() {
    case "$1" in
        *" "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Concurrent wrap cells. SOURCE_WRAP_PARALLEL wins, else MAX_PARALLEL, else 2.
# Floor at 1 so a bad value cannot fork-bomb; compile is never included.
source_build_wrap_parallel_limit() {
    local max="${SOURCE_WRAP_PARALLEL:-${MAX_PARALLEL:-2}}"
    case "$max" in
        ''|*[!0-9]*) max=2 ;;
    esac
    [ "$max" -lt 1 ] && max=1
    printf '%s' "$max"
}

# Architectures for a source build come from the config's `architectures:`
# (source mode has no release assets to auto-discover, so the release-asset
# architecture filter used by the binary path does not apply).
source_build_architectures() {
    get_supported_architectures
}

# Stable id for a baked image. Changes when the recipe, suite, mode, base
# image, build_depends, or apt overlay changes.
source_build_image_fingerprint() {
    local dist="$1" mode="$2" base_image="$3"
    local extra_sources="$4" override_from="$5" override_pkgs="$6"
    local build_deps="${7:-${BUILD_DEPENDS:-}}"
    printf '%s\0' \
        "$SOURCE_BUILD_IMAGE_RECIPE" \
        "$dist" "$mode" "$base_image" \
        "$build_deps" "$extra_sources" "$override_from" "$override_pkgs" \
        | sha256sum | awk '{print $1}'
}

source_build_image_tag() {
    local dist="$1" mode="$2" fp="$3"
    local pkg
    pkg="$(printf '%s' "${PACKAGE_NAME:-pkg}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')"
    printf 'srcbld-%s-%s-%s-%s' "$pkg" "$dist" "$mode" "${fp:0:12}"
}

source_build_image_tar() {
    local tag="$1"
    local dl_cache="${DOWNLOAD_CACHE_DIR:-/tmp/download_cache}"
    printf '%s/images/%s.tar.gz' "$dl_cache" "$tag"
}

# Dockerfile for a source-builder image. extra_sources non-empty means the
# build context must contain extra.list (COPY'd into apt sources).
source_build_dockerfile() {
    local base_image="$1" mode="$2" extra_sources="$3"
    local override_from="$4" override_pkgs="$5" build_deps="$6"

    printf 'FROM %s\n' "$base_image"
    printf 'ENV DEBIAN_FRONTEND=noninteractive\n'
    if [ -n "$extra_sources" ]; then
        printf 'COPY extra.list /etc/apt/sources.list.d/source-build-extra.list\n'
    fi
    printf 'RUN apt-get update -qq && apt-get install -y'
    if [ "$mode" = "wrap" ]; then
        printf ' file dpkg-dev'
    else
        printf ' build-essential cmake ninja-build pkg-config file curl ca-certificates dpkg-dev ccache lld'
    fi
    if [ -n "$build_deps" ]; then
        printf ' %s' "$build_deps"
    fi
    if [ -n "$override_from" ] && [ -n "$override_pkgs" ]; then
        printf ' && apt-get install -y -t %s %s' "$override_from" "$override_pkgs"
    fi
    printf ' && rm -rf /var/lib/apt/lists/*\n'
}

# Bake (or load) the per-suite image. Prints the docker tag on stdout.
# info/warning already go to stderr, so the tag is capture-safe.
source_build_bake_image() {
    local dist="$1" mode="$2" extra_sources="$3" override_from="$4" override_pkgs="$5"
    local base_image fp tag tar_path ctx

    base_image="$(base_image_for_dist "$dist")"
    fp="$(source_build_image_fingerprint "$dist" "$mode" "$base_image" \
        "$extra_sources" "$override_from" "$override_pkgs")"
    tag="$(source_build_image_tag "$dist" "$mode" "$fp")"
    tar_path="$(source_build_image_tar "$tag")"

    if docker image inspect "$tag" >/dev/null 2>&1; then
        info "Using baked image $tag"
        printf '%s' "$tag"
        return 0
    fi

    mkdir -p "$(dirname "$tar_path")"
    if [ -s "$tar_path" ]; then
        info "Loading baked image $tag"
        if gunzip -c "$tar_path" | docker load >/dev/null \
            && docker image inspect "$tag" >/dev/null 2>&1; then
            printf '%s' "$tag"
            return 0
        fi
        warning "Failed to load $tar_path; rebuilding"
        rm -f "$tar_path"
    fi

    ctx="$(mktemp -d)"
    source_build_dockerfile "$base_image" "$mode" "$extra_sources" \
        "$override_from" "$override_pkgs" "${BUILD_DEPENDS:-}" > "$ctx/Dockerfile"
    if [ -n "$extra_sources" ]; then
        printf '%s\n' "$extra_sources" > "$ctx/extra.list"
    fi

    info "Baking $tag"
    if ! docker build -t "$tag" "$ctx"; then
        rm -rf "$ctx"
        return 1
    fi
    rm -rf "$ctx"

    # Persistence is the chroot tarball (source_build_ensure_rootfs). The
    # image stays in the daemon for this job; docker import covers fallback.
    printf '%s' "$tag"
}

# unshare (user ns) > sudo chroot > docker run. Override with SOURCE_BUILD_BACKEND.
source_build_resolve_backend() {
    local want="${SOURCE_BUILD_BACKEND:-auto}"
    case "$want" in
        unshare|sudo|docker)
            printf '%s' "$want"
            return 0
            ;;
    esac
    if unshare --map-root-user --mount --fork true >/dev/null 2>&1; then
        printf '%s' unshare
    elif sudo -n true >/dev/null 2>&1; then
        printf '%s' sudo
    else
        printf '%s' docker
    fi
}

source_build_chroot_tar() {
    local tag="$1"
    local dl_cache="${DOWNLOAD_CACHE_DIR:-/tmp/download_cache}"
    printf '%s/chroots/%s.tar.gz' "$dl_cache" "$tag"
}

source_build_chroot_dest() {
    local tag="$1"
    printf '%s/%s' "${SOURCE_CHROOT_DIR:-$PWD/.source-chroot}" "$tag"
}

# Cell body. Runs inside the chroot or container; reads env (PACKAGE_NAME, MODE, …).
source_build_write_inner_script() {
    local path="${1:-.source-stage/inner.sh}"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<'INNER'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if [ "${SOURCE_BUILD_BAKED:-}" != "1" ]; then
    if [ -n "${EXTRA_SOURCES:-}" ]; then
        printf "%s\n" "$EXTRA_SOURCES" > /etc/apt/sources.list.d/source-build-extra.list
    fi
    apt-get update -qq
    if [ "${MODE:-compile}" = "wrap" ]; then
        apt-get install -y -qq file dpkg-dev $BUILD_DEPS >/dev/null
    else
        apt-get install -y -qq \
            build-essential cmake ninja-build pkg-config file \
            curl ca-certificates dpkg-dev ccache lld $BUILD_DEPS >/dev/null
        if [ -n "${OVERRIDE_FROM:-}" ] && [ -n "${OVERRIDE_PKGS:-}" ]; then
            apt-get install -y -qq -t "$OVERRIDE_FROM" $OVERRIDE_PKGS >/dev/null
        fi
    fi
fi

mkdir -p /src /build /stage
if [ "${MODE:-compile}" = "wrap" ]; then
    if [ -z "${STAGE_REL:-}" ] || [ ! -s "/out/${STAGE_REL}" ]; then
        echo "ERROR: compiled stage /out/${STAGE_REL:-?} missing" >&2
        exit 1
    fi
    echo "::group::extract stage ${STAGE_REL}"
    tar -xzf "/out/${STAGE_REL}" -C /stage
    echo "::endgroup::"
else
    if [ ! -s "/cache/$TARBALL" ]; then
        echo "ERROR: cached source tarball /cache/$TARBALL missing" >&2
        exit 1
    fi
    echo "::group::extract /cache/$TARBALL"
    tar -xf "/cache/$TARBALL" -C /src --strip-components=1
    echo "::endgroup::"

    cmake_launchers=""
    if command -v ccache >/dev/null 2>&1; then
        export CCACHE_DIR=/ccache
        export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-2G}"
        mkdir -p "$CCACHE_DIR"
        cmake_launchers="-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
    fi
    linker_flags=""
    if command -v mold >/dev/null 2>&1; then
        linker_flags="-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=mold -DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=mold"
    elif command -v ld.lld >/dev/null 2>&1; then
        linker_flags="-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld -DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld"
    fi
    cmake -S /src -B /build -G Ninja \
        -DCMAKE_INSTALL_PREFIX=/usr $cmake_launchers $linker_flags $CMAKE_FLAGS
    cmake --build /build
    if command -v ccache >/dev/null 2>&1; then
        echo "::group::ccache stats"
        ccache -s || true
        echo "::endgroup::"
    fi
    DESTDIR=/stage cmake --install /build

    if [ -n "${STAGE_REL:-}" ]; then
        mkdir -p "$(dirname "/out/${STAGE_REL}")"
        tar -C /stage -czf "/out/${STAGE_REL}" .
    fi
fi
mkdir -p /stage/DEBIAN

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
    -exec sh -c 'file -b "$1" | grep -q "^ELF" && echo "$1"' _ {} \; 2>/dev/null)
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

if [ "${LINTIAN:-false}" = "true" ]; then
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -qq lintian >/dev/null 2>&1 || true
    lintian --no-tag-display-limit "/out/${DEB}" \
        || echo "::warning::lintian reported findings for ${DEB}"
fi
INNER
    chmod +x "$path"
}

# Bind-mount host dirs and chroot. Used under unshare or sudo; do not exec so
# the sudo caller can umount.
source_build_write_enter_chroot() {
    local path="${1:-.source-stage/enter-chroot.sh}"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<'ENTER'
#!/bin/bash
set -euo pipefail
dest=$1
host_pwd=$2
host_cache=$3
host_ccache=$4
mode=$5
env_name=$6
mkdir -p "$dest/out" "$dest/cache" "$dest/ccache" "$dest/build" "$dest/proc" "$dest/dev"
mount --bind "$host_pwd" "$dest/out"
mount --bind "$host_cache" "$dest/cache"
if [ "$mode" = "compile" ] && [ -n "$host_ccache" ] && [ -d "$host_ccache" ]; then
    mount --bind "$host_ccache" "$dest/ccache"
fi
mount -t proc proc "$dest/proc"
if [ -d /dev ]; then
    mount --bind /dev "$dest/dev"
fi
if [ -f /etc/resolv.conf ]; then
    mkdir -p "$dest/etc"
    cp /etc/resolv.conf "$dest/etc/resolv.conf" 2>/dev/null || true
fi
chroot "$dest" /bin/bash -c "set -a; source /out/.source-stage/${env_name}; set +a; cd /build; exec /bin/bash /out/.source-stage/inner.sh"
ENTER
    chmod +x "$path"
}

# Bake (if needed), export a chroot tarball, unpack to dest. Prints dest.
source_build_ensure_rootfs() {
    local dist="$1" mode="$2" extra_sources="$3" override_from="$4" override_pkgs="$5"
    local base_image fp tag chroot_tar dest cid image

    base_image="$(base_image_for_dist "$dist")"
    fp="$(source_build_image_fingerprint "$dist" "$mode" "$base_image" \
        "$extra_sources" "$override_from" "$override_pkgs")"
    tag="$(source_build_image_tag "$dist" "$mode" "$fp")"
    SOURCE_BUILD_LAST_TAG="$tag"
    chroot_tar="$(source_build_chroot_tar "$tag")"
    dest="$(source_build_chroot_dest "$tag")"

    if [ -d "$dest/usr" ]; then
        info "Using unpacked chroot $dest"
        printf '%s' "$dest"
        return 0
    fi

    mkdir -p "$(dirname "$chroot_tar")" "$dest"
    if [ -s "$chroot_tar" ]; then
        info "Unpacking chroot $tag"
        tar -xzf "$chroot_tar" -C "$dest"
        mkdir -p "$dest/out" "$dest/cache" "$dest/ccache" "$dest/build" "$dest/src"
        printf '%s' "$dest"
        return 0
    fi

    image="$(source_build_bake_image "$dist" "$mode" "$extra_sources" "$override_from" "$override_pkgs")" || return 1
    info "Exporting chroot $tag"
    cid="$(docker create "$image")" || return 1
    if ! docker export "$cid" | tar -C "$dest" -xf -; then
        docker rm "$cid" >/dev/null 2>&1 || true
        rm -rf "$dest"
        return 1
    fi
    docker rm "$cid" >/dev/null 2>&1 || true
    mkdir -p "$dest/out" "$dest/cache" "$dest/ccache" "$dest/build" "$dest/src"
    # Volatile/runtime dirs (systemd's /run entries are unreadable as a
    # non-root user) are excluded: the chroot recreates what it needs.
    if tar -C "$dest" --exclude=./run --exclude=./tmp --exclude=./proc \
        --exclude=./sys --exclude=./dev -czf "$chroot_tar.tmp" .; then
        mv "$chroot_tar.tmp" "$chroot_tar"
    else
        rm -f "$chroot_tar.tmp"
        warning "Failed to cache chroot tarball $tag (rootfs is usable this run)"
    fi
    printf '%s' "$dest"
}

source_build_run_in_chroot() {
    local dest="$1" mode="$2" env_name="$3" ccache_dir="$4" dl_cache="$5"
    local backend enter
    backend="$(source_build_resolve_backend)"
    enter=".source-stage/enter-chroot.sh"
    source_build_write_enter_chroot "$enter"
    case "$backend" in
        unshare)
            unshare --map-root-user --mount --fork \
                /bin/bash "$enter" "$dest" "$PWD" "$dl_cache" "$ccache_dir" "$mode" "$env_name"
            ;;
        sudo)
            sudo /bin/bash "$enter" "$dest" "$PWD" "$dl_cache" "$ccache_dir" "$mode" "$env_name"
            sudo umount -l "$dest/out" "$dest/cache" "$dest/ccache" "$dest/proc" "$dest/dev" 2>/dev/null || true
            ;;
        *)
            return 1
            ;;
    esac
}

# Underscore is legal in the .deb filename but NOT in the Version field,
# so the arch suffix lives in the filename only (binary path does the
# same: Version ...+${dist}, file ...+${dist}_${arch}.deb). Prints
# "<filename-version> <control-version>".
source_build_versions() {
    local dist="$1" build_arch="$2"
    local debian_version
    debian_version=$(echo "$VERSION" | sed -E 's/^[^0-9]*//')
    printf '%s %s' \
        "${debian_version}-${BUILD_VERSION}+${dist}_${build_arch}" \
        "${debian_version}-${BUILD_VERSION}+${dist}"
}

# Build one suite/arch cell and leave the .deb in the current directory.
# mode=compile: cmake in debian:<dist>, export the install tree to stage_rel,
#   then wrap that suite's .deb.
# mode=wrap: reuse the compiled tree at stage_rel, shlibdeps + dpkg-deb only.
# Returns non-zero on any failure so the caller can keep going with other
# cells rather than aborting the whole run.
build_source_distribution() {
    local build_arch="$1" dist="$2"
    local mode="${3:-compile}"
    local stage_rel="${4:-}"

    # Debian policy requires the Version field to start with a digit; strip
    # any non-digit prefix from the upstream tag (v0.3.1 -> 0.3.1). The
    # underscore arch suffix is filename-only (see source_build_versions).
    local full_version deb_version
    read -r full_version deb_version <<< "$(source_build_versions "$dist" "$build_arch")"
    local deb="${PACKAGE_NAME}_${full_version}.deb"

    # The ref to fetch: explicit upstream_ref wins, else the raw version tag.
    local ref="${UPSTREAM_REF:-$VERSION}"

    # Cache the source tarball on the host (defaults to the template's
    # /tmp/download_cache) so re-runs and the other suites reuse one download
    # instead of curling inside every container. Wrap cells do not need it.
    local dl_cache="${DOWNLOAD_CACHE_DIR:-/tmp/download_cache}"
    mkdir -p "$dl_cache"
    local safe_ref="${ref//\//_}"
    local tarball="${PACKAGE_NAME}-${safe_ref}.tar.gz"
    if [ "$mode" = "compile" ]; then
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
    elif [ ! -s "./$stage_rel" ]; then
        warning "Compiled stage missing: $stage_rel"
        return 1
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
    # (ext-background-effect-v1). Wrap cells skip this: they do not compile.
    local override_from override_pkgs extra_sources
    override_from=""
    override_pkgs=""
    extra_sources=""
    if [ "$mode" = "compile" ]; then
        override_from="$(yq eval ".build_depends_suites.\"$dist\".from // \"\"" "$CONFIG_FILE" 2>/dev/null || true)"
        if [ "$override_from" = "null" ] || [ -z "$override_from" ]; then
            override_from=""
        fi
        override_pkgs="$(yq eval "((.build_depends_suites.\"$dist\".packages // []) | join(\" \"))" "$CONFIG_FILE" 2>/dev/null || true)"
        if [ "$override_pkgs" = "null" ]; then
            override_pkgs=""
        fi
        if [ -n "$override_from" ]; then
            extra_sources="$(yq eval "(.build_apt_sources.\"$override_from\" // []) | .[]" "$CONFIG_FILE" 2>/dev/null || true)"
        fi
    fi

    local ccache_dir=""
    if [ "$mode" = "compile" ]; then
        ccache_dir="${SOURCE_CCACHE_DIR:-$dl_cache/ccache}"
        mkdir -p "$ccache_dir"
    fi

    mkdir -p .source-stage
    source_build_write_inner_script .source-stage/inner.sh
    local env_name="cell-${dist}-${mode}.env"
    {
        printf 'export PACKAGE_NAME=%s\n' "$(printf '%q' "$PACKAGE_NAME")"
        printf 'export FULL_VERSION=%s\n' "$(printf '%q' "$deb_version")"
        printf 'export DEB=%s\n' "$(printf '%q' "$deb")"
        printf 'export ARCH=%s\n' "$(printf '%q' "$build_arch")"
        printf 'export SUITE=%s\n' "$(printf '%q' "$dist")"
        printf 'export REF=%s\n' "$(printf '%q' "$ref")"
        printf 'export BUILD_DEPS=%s\n' "$(printf '%q' "${BUILD_DEPENDS:-}")"
        printf 'export CMAKE_FLAGS=%s\n' "$(printf '%q' "${CMAKE_FLAGS:-}")"
        printf 'export MAINTAINER=%s\n' "$(printf '%q' "$PACKAGE_MAINTAINER")"
        printf 'export DESCRIPTION=%s\n' "$(printf '%q' "$PACKAGE_DESCRIPTION")"
        printf 'export LINTIAN=%s\n' "$(printf '%q' "$lintian")"
        printf 'export EXTRA_SOURCES=%s\n' "$(printf '%q' "${extra_sources:-}")"
        printf 'export OVERRIDE_FROM=%s\n' "$(printf '%q' "${override_from:-}")"
        printf 'export OVERRIDE_PKGS=%s\n' "$(printf '%q' "${override_pkgs:-}")"
        printf 'export TARBALL=%s\n' "$(printf '%q' "$tarball")"
        printf 'export MODE=%s\n' "$(printf '%q' "$mode")"
        printf 'export STAGE_REL=%s\n' "$(printf '%q' "$stage_rel")"
        printf 'export CCACHE_MAXSIZE=%s\n' "$(printf '%q' "${SOURCE_CCACHE_MAXSIZE:-2G}")"
    } > ".source-stage/$env_name"

    local backend dest baked=0 run_image="$base_image"
    backend="$(source_build_resolve_backend)"
    SOURCE_BUILD_LAST_TAG=""
    SOURCE_BUILD_LAST_DEST=""
    if dest="$(source_build_ensure_rootfs "$dist" "$mode" "$extra_sources" "$override_from" "$override_pkgs")"; then
        baked=1
        SOURCE_BUILD_LAST_DEST="$dest"
    else
        dest=""
        warning "Rootfs prepare failed for $dist/$mode; falling back to docker"
        backend=docker
    fi
    printf 'export SOURCE_BUILD_BAKED=%s\n' "$(printf '%q' "$baked")" >> ".source-stage/$env_name"

    local docker_log="/tmp/source-build-${dist}-${build_arch}.log"
    if [ "$mode" = "wrap" ]; then
        info "Wrapping $PACKAGE_NAME $ref ($backend $dist/$build_arch) from $stage_rel..."
    else
        info "Compiling $PACKAGE_NAME $ref ($backend $dist/$build_arch)..."
    fi

    local rc=0
    if [ "$backend" != "docker" ] && [ -n "$dest" ] && [ -d "$dest/usr" ]; then
        source_build_run_in_chroot "$dest" "$mode" "$env_name" "$ccache_dir" "$dl_cache" \
            2>&1 | tee "$docker_log"
        rc=${PIPESTATUS[0]}
    else
        if ! command -v docker >/dev/null 2>&1; then
            error "docker is required for build_mode: source when chroot is unavailable" "docker_missing"
        fi
        if [ -n "${SOURCE_BUILD_LAST_TAG:-}" ] \
            && docker image inspect "$SOURCE_BUILD_LAST_TAG" >/dev/null 2>&1; then
            run_image="$SOURCE_BUILD_LAST_TAG"
        elif [ -n "${SOURCE_BUILD_LAST_TAG:-}" ] \
            && [ -s "$(source_build_chroot_tar "$SOURCE_BUILD_LAST_TAG")" ]; then
            info "Importing chroot tarball as $SOURCE_BUILD_LAST_TAG"
            docker import "$(source_build_chroot_tar "$SOURCE_BUILD_LAST_TAG")" "$SOURCE_BUILD_LAST_TAG" >/dev/null
            run_image="$SOURCE_BUILD_LAST_TAG"
        elif baked_image="$(source_build_bake_image "$dist" "$mode" "$extra_sources" "$override_from" "$override_pkgs")"; then
            run_image="$baked_image"
            baked=1
            printf 'export SOURCE_BUILD_BAKED=%s\n' "$(printf '%q' "$baked")" >> ".source-stage/$env_name"
        fi
        local docker_ccache=()
        if [ "$mode" = "compile" ]; then
            docker_ccache=(-v "$ccache_dir:/ccache")
        fi
        docker run --rm \
            -v "$PWD:/out" \
            -v "$dl_cache:/cache:ro" \
            -v "$apt_cache:/var/cache/apt/archives" \
            "${docker_ccache[@]}" \
            -w /build \
            "$run_image" \
            bash -c "set -a; source /out/.source-stage/${env_name}; set +a; exec /bin/bash /out/.source-stage/inner.sh" \
            2>&1 | tee "$docker_log"
        rc=${PIPESTATUS[0]}
    fi
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
    if [ "$mode" = "compile" ] && [ -n "$stage_rel" ] && [ ! -s "./$stage_rel" ]; then
        warning "Compile produced no stage tarball: $stage_rel"
        return 1
    fi
    success "Built $deb"
    return 0
}

# Unpack wrap chroots one suite at a time so parallel wrap cells only enter them.
source_build_prebake_wrap_images() {
    local suite
    for suite in $1; do
        info "Pre-baking wrap rootfs for $suite"
        if ! source_build_ensure_rootfs "$suite" wrap "" "" "" >/dev/null; then
            warning "Pre-bake failed for $suite; wrap cell will retry/fallback"
        fi
    done
}

# Run wrap cells concurrently, capped by source_build_wrap_parallel_limit.
# Each cell's log is replayed in start order after wait so CI stays readable.
# Increments built/failed in the caller (bash dynamic scope).
source_build_run_wraps() {
    local build_arch="$1" stage_rel="$2" wrap_list="$3"
    local max suite pid rc log i running
    local -a pids=()
    local -a started=()

    max="$(source_build_wrap_parallel_limit)"
    info "Wrapping $wrap_list (max $max concurrent)"
    source_build_prebake_wrap_images "$wrap_list"

    running=0
    for suite in $wrap_list; do
        while [ "$running" -ge "$max" ]; do
            wait -n || true
            running=$((running - 1))
        done
        log="source-wrap-${build_arch}-${suite}.log"
        build_source_distribution "$build_arch" "$suite" wrap "$stage_rel" >"$log" 2>&1 &
        pids+=($!)
        started+=("$suite")
        running=$((running + 1))
    done

    i=0
    for pid in "${pids[@]}"; do
        suite="${started[$i]}"
        i=$((i + 1))
        rc=0
        wait "$pid" || rc=$?
        log="source-wrap-${build_arch}-${suite}.log"
        if [ -f "$log" ]; then
            cat "$log"
            rm -f "$log"
        fi
        if [ "$rc" -eq 0 ]; then
            built=$((built + 1))
        else
            failed=$((failed + 1))
            warning "Source wrap failed for $suite/$build_arch"
        fi
    done
}

# Compile once on the oldest suite in $2, wrap the rest. $1 is the arch.
# Increments built/failed in the caller (bash dynamic scope).
source_build_family() {
    local build_arch="$1"
    local suites="$2"
    [ -n "$suites" ] || return 0

    local compile_suite stage_rel suite wrap_list
    compile_suite="$(source_build_oldest_suite "$suites")"
    stage_rel=".source-stage/${PACKAGE_NAME}-${build_arch}-${compile_suite}.tar.gz"
    mkdir -p .source-stage
    wrap_list="$(source_build_wrap_suites "$suites" "$compile_suite")"
    if [ -n "$wrap_list" ]; then
        info "Source build $build_arch: compile on $compile_suite, wrap $wrap_list"
    else
        info "Source build $build_arch: compile on $compile_suite (single suite)"
    fi

    if build_source_distribution "$build_arch" "$compile_suite" compile "$stage_rel"; then
        built=$((built + 1))
    else
        failed=$((failed + 1))
        warning "Compile failed for $compile_suite/$build_arch; skipping wraps of this family"
        return 0
    fi

    if source_build_wrap_is_parallel "$wrap_list"; then
        source_build_run_wraps "$build_arch" "$stage_rel" "$wrap_list"
        return 0
    fi

    for suite in $wrap_list; do
        if build_source_distribution "$build_arch" "$suite" wrap "$stage_rel"; then
            built=$((built + 1))
        else
            failed=$((failed + 1))
            warning "Source wrap failed for $suite/$build_arch"
        fi
    done
}

# One matrix cell per arch: honor the requested architecture instead of
# building every arch on every runner (which would mislabel e.g. arm64
# output compiled on an amd64 host). Prints the filtered arch list.
source_build_requested_arches() {
    local arches="$1"
    if [ -n "${ARCH:-}" ] && [ "$ARCH" != "all" ]; then
        if ! printf '%s\n' "$arches" | grep -qx "$ARCH"; then
            error "Requested architecture '$ARCH' is not in architectures: ($(echo "$arches" | tr '\n' ' '))" "config_invalid"
        fi
        printf '%s' "$ARCH"
        return 0
    fi
    printf '%s' "$arches"
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

    # One matrix cell per arch: honor the requested architecture instead of
    # building every arch on every runner (which would mislabel e.g. arm64
    # output compiled on an amd64 host).
    arches="$(source_build_requested_arches "$arches")"

    local suites
    suites="$(source_build_suites)"
    if [ -z "$suites" ]; then
        error "No suites to build (build_suites/distributions resolved empty)" "config_invalid"
    fi

    info "Source build: $PACKAGE_NAME $VERSION-$BUILD_VERSION (compile-once per family)"
    info "Suites: $suites"
    info "Architectures: $(echo "$arches" | tr '\n' ' ')"

    local built=0 failed=0 arch
    for arch in $arches; do
        source_build_family "$arch" "$(source_build_filter_debian "$suites")"
        source_build_family "$arch" "$(source_build_filter_ubuntu "$suites")"
    done

    if [ "$built" -eq 0 ]; then
        error "No packages were built from source" "source_build_failed"
    fi
    [ "$failed" -eq 0 ] || warning "$failed source build cell(s) failed"
    # Chroot files may be root-owned (sudo backend); escalate the removal
    # and never let cleanup fail the build (main.sh runs under set -e).
    rm -rf .source-stage 2>/dev/null || true
    if [ "$failed" -eq 0 ]; then
        if ! rm -rf .source-chroot 2>/dev/null; then
            sudo rm -rf .source-chroot 2>/dev/null \
                || warning "Could not remove .source-chroot (root-owned leftovers)"
        fi
    fi

    ls -lh ${PACKAGE_NAME}_*.deb 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || true

    # Emit .dsc source packages from the built binaries, same as the binary
    # path (best-effort; the .debs stand on their own if this fails).
    if ! command -v build_source_packages >/dev/null 2>&1; then
        source "$SCRIPT_DIR/lib/source-package.sh"
    fi
    build_source_packages

    return 0
}
