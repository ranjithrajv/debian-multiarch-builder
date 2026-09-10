#!/bin/bash

# Test script for build_mode: source (src/lib/source-build.sh + the
# package.yaml fields config.sh parses for it). Does not require Docker: it
# covers config parsing and suite selection, which is where regressions would
# silently change what gets built.

set -e

export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/src" && pwd)"
source src/lib/source-build.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_TOTAL=0
TESTS_FAILED=0

check() {
    local label="$1" got="$2" expected="$3"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ "$got" = "$expected" ]; then
        echo -e "${GREEN}✅ PASS${NC}: $label"
    else
        echo -e "${RED}❌ FAIL${NC}: $label -> '$got' (expected '$expected')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# --- source_build_enabled -------------------------------------------------
BUILD_MODE=source
source_build_enabled && got=yes || got=no
check "build_mode=source enables the source path" "$got" "yes"

BUILD_MODE=binary
source_build_enabled && got=yes || got=no
check "build_mode=binary stays on the binary path" "$got" "no"

unset BUILD_MODE
source_build_enabled && got=yes || got=no
check "unset build_mode defaults to binary" "$got" "no"

# --- source_build_suites --------------------------------------------------
# Explicit build_suites takes precedence and skip_suites is subtracted.
BUILD_SUITES="trixie forky sid"; SKIP_SUITES="forky"; DISTRIBUTIONS="bookworm"
check "build_suites wins over distributions, skip_suites subtracted" \
    "$(source_build_suites)" "trixie sid"

# No build_suites -> fall back to DISTRIBUTIONS, still applying skip_suites.
BUILD_SUITES=""; SKIP_SUITES="sid"; DISTRIBUTIONS="bookworm trixie sid"
check "empty build_suites falls back to distributions" \
    "$(source_build_suites)" "bookworm trixie"

BUILD_SUITES=""; SKIP_SUITES=""; DISTRIBUTIONS="trixie sid"
check "no skip_suites keeps the full suite list" \
    "$(source_build_suites)" "trixie sid"

# --- compile-once plan (oldest suite + wrap the rest) ---------------------
check "oldest of trixie/forky/sid is trixie" \
    "$(source_build_oldest_suite "trixie forky sid")" "trixie"
check "oldest of sid/forky is forky" \
    "$(source_build_oldest_suite "sid forky")" "forky"
check "single suite compiles on itself" \
    "$(source_build_oldest_suite "sid")" "sid"
check "oldest of forky/trixie/bookworm is bookworm" \
    "$(source_build_oldest_suite "forky trixie bookworm")" "bookworm"
check "unknown suite names fall back to the first entry" \
    "$(source_build_oldest_suite "foo bar")" "foo"
check "oldest Ubuntu of noble/jammy is jammy" \
    "$(source_build_oldest_suite "noble jammy")" "jammy"

check "wrap suites drop the compile suite" \
    "$(source_build_wrap_suites "trixie forky sid" "trixie")" "forky sid"
check "wrap suites empty when only the compile suite is present" \
    "$(source_build_wrap_suites "trixie" "trixie")" ""

source_build_wrap_is_parallel "forky sid" && got=yes || got=no
check "two wrap suites run in parallel" "$got" "yes"
source_build_wrap_is_parallel "forky" && got=yes || got=no
check "one wrap suite stays sequential" "$got" "no"
source_build_wrap_is_parallel "" && got=yes || got=no
check "empty wrap list stays sequential" "$got" "no"

unset SOURCE_WRAP_PARALLEL MAX_PARALLEL
check "wrap parallel default is 2" "$(source_build_wrap_parallel_limit)" "2"
MAX_PARALLEL=4
check "wrap parallel follows MAX_PARALLEL" "$(source_build_wrap_parallel_limit)" "4"
SOURCE_WRAP_PARALLEL=3
MAX_PARALLEL=8
check "SOURCE_WRAP_PARALLEL wins over MAX_PARALLEL" "$(source_build_wrap_parallel_limit)" "3"
SOURCE_WRAP_PARALLEL=0
check "wrap parallel floor is 1" "$(source_build_wrap_parallel_limit)" "1"
SOURCE_WRAP_PARALLEL=bogus
check "non-numeric wrap parallel falls back to 2" "$(source_build_wrap_parallel_limit)" "2"
unset SOURCE_WRAP_PARALLEL MAX_PARALLEL

SOURCE_BUILD_BACKEND=docker
check "backend override docker" "$(source_build_resolve_backend)" "docker"
SOURCE_BUILD_BACKEND=unshare
check "backend override unshare" "$(source_build_resolve_backend)" "unshare"
SOURCE_BUILD_BACKEND=sudo
check "backend override sudo" "$(source_build_resolve_backend)" "sudo"
unset SOURCE_BUILD_BACKEND
case "$(source_build_resolve_backend)" in
    unshare|sudo|docker) got=yes ;;
    *) got=no ;;
esac
check "auto backend is unshare, sudo, or docker" "$got" "yes"

check "debian filter drops Ubuntu suites" \
    "$(source_build_filter_debian "trixie jammy sid noble")" "trixie sid"
check "ubuntu filter drops Debian suites" \
    "$(source_build_filter_ubuntu "trixie jammy sid noble")" "jammy noble"
check "debian filter of Ubuntu-only is empty" \
    "$(source_build_filter_debian "jammy noble")" ""

source_build_oldest_suite "" >/dev/null && got=ok || got=fail
check "oldest suite of an empty list fails" "$got" "fail"

# --- baked image recipe (no Docker) ---------------------------------------
PACKAGE_NAME=quickshell
SOURCE_BUILD_IMAGE_RECIPE=3
df_compile="$(source_build_dockerfile "debian:trixie" "compile" "" "" "" "qt6-base-dev libvulkan-dev")"
df_wrap="$(source_build_dockerfile "debian:forky" "wrap" "" "" "" "qt6-base-dev libvulkan-dev")"
df_overlay="$(source_build_dockerfile "debian:trixie" "compile" "deb http://deb.debian.org/debian forky main" "forky" "wayland-protocols" "qt6-base-dev")"

echo "$df_compile" | grep -q ccache && got=yes || got=no
check "compile dockerfile installs ccache" "$got" "yes"
echo "$df_compile" | grep -q ' ccache lld' && got=yes || got=no
check "compile dockerfile installs lld" "$got" "yes"
echo "$df_wrap" | grep -q lld && got=yes || got=no
check "wrap dockerfile does not install lld" "$got" "no"
echo "$df_compile" | grep -q cmake && got=yes || got=no
check "compile dockerfile installs cmake" "$got" "yes"
echo "$df_compile" | grep -q qt6-base-dev && got=yes || got=no
check "compile dockerfile installs build_depends" "$got" "yes"
echo "$df_compile" | grep -q 'COPY extra.list' && got=yes || got=no
check "compile dockerfile omits extra.list when there is no overlay" "$got" "no"

echo "$df_wrap" | grep -q ccache && got=yes || got=no
check "wrap dockerfile does not install ccache" "$got" "no"
echo "$df_wrap" | grep -q cmake && got=yes || got=no
check "wrap dockerfile does not install cmake" "$got" "no"
echo "$df_wrap" | grep -q build-essential && got=yes || got=no
check "wrap dockerfile does not install build-essential" "$got" "no"
echo "$df_wrap" | grep -q 'file dpkg-dev' && got=yes || got=no
check "wrap dockerfile installs file and dpkg-dev" "$got" "yes"
echo "$df_wrap" | grep -q qt6-base-dev && got=yes || got=no
check "wrap dockerfile still installs build_depends for shlibdeps" "$got" "yes"

echo "$df_overlay" | grep -q 'COPY extra.list' && got=yes || got=no
check "overlay dockerfile copies extra.list" "$got" "yes"
echo "$df_overlay" | grep -q -- '-t forky wayland-protocols' && got=yes || got=no
check "overlay dockerfile pins override packages" "$got" "yes"

fp_a="$(source_build_image_fingerprint trixie compile debian:trixie "" "" "" "qt6-base-dev")"
fp_b="$(source_build_image_fingerprint trixie compile debian:trixie "" "" "" "qt6-base-dev")"
fp_c="$(source_build_image_fingerprint trixie compile debian:trixie "" "" "" "qt6-base-dev libvulkan-dev")"
fp_d="$(source_build_image_fingerprint trixie wrap debian:trixie "" "" "" "qt6-base-dev")"
check "fingerprint is stable for the same inputs" "$fp_a" "$fp_b"
[ "$fp_a" != "$fp_c" ] && got=yes || got=no
check "fingerprint changes when build_depends change" "$got" "yes"
[ "$fp_a" != "$fp_d" ] && got=yes || got=no
check "fingerprint changes between compile and wrap" "$got" "yes"

check "image tag format" \
    "$(source_build_image_tag trixie compile abcdef1234567890)" \
    "srcbld-quickshell-trixie-compile-abcdef123456"

DOWNLOAD_CACHE_DIR=/tmp/dl-cache-test
check "image tar lives under download_cache/images" \
    "$(source_build_image_tar srcbld-quickshell-trixie-compile-abcdef123456)" \
    "/tmp/dl-cache-test/images/srcbld-quickshell-trixie-compile-abcdef123456.tar.gz"
check "chroot tar lives under download_cache/chroots" \
    "$(source_build_chroot_tar srcbld-quickshell-trixie-compile-abcdef123456)" \
    "/tmp/dl-cache-test/chroots/srcbld-quickshell-trixie-compile-abcdef123456.tar.gz"
unset DOWNLOAD_CACHE_DIR
SOURCE_CHROOT_DIR=/tmp/chroot-test
check "chroot dest uses SOURCE_CHROOT_DIR" \
    "$(source_build_chroot_dest srcbld-quickshell-trixie-compile-abcdef123456)" \
    "/tmp/chroot-test/srcbld-quickshell-trixie-compile-abcdef123456"
unset SOURCE_CHROOT_DIR

ARCH=amd64
check "requested arch filters to one" \
    "$(source_build_requested_arches "$(printf 'amd64\narm64')")" "amd64"
ARCH=all
check "ARCH=all keeps the full list" \
    "$(source_build_requested_arches "$(printf 'amd64\narm64')")" "$(printf 'amd64\narm64')"
unset ARCH
check "unset ARCH keeps the full list" \
    "$(source_build_requested_arches "$(printf 'amd64\narm64')")" "$(printf 'amd64\narm64')"

# Version field must not carry the _arch suffix (dpkg rejects _ in revision).
VERSION=v0.3.1 BUILD_VERSION=2
check "filename version keeps arch suffix" \
    "$(source_build_versions trixie amd64)" "0.3.1-2+trixie_amd64 0.3.1-2+trixie"
VERSION=bun-v1.3.14 BUILD_VERSION=1
check "filename version strips tag prefix" \
    "$(source_build_versions sid arm64)" "1.3.14-1+sid_arm64 1.3.14-1+sid"
unset VERSION BUILD_VERSION

# --- package.yaml parsing (mirrors config.sh) -----------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

source_build_write_inner_script "$TMP/inner.sh"
source_build_write_enter_chroot "$TMP/enter-chroot.sh"
bash -n "$TMP/inner.sh" && got=ok || got=fail
check "inner.sh is valid bash" "$got" "ok"
bash -n "$TMP/enter-chroot.sh" && got=ok || got=fail
check "enter-chroot.sh is valid bash" "$got" "ok"

cat > "$TMP/source.yaml" <<'YAML'
package_name: quickshell
github_repo: quickshell-mirror/quickshell
build_mode: source
build_system: cmake
upstream_url: https://git.outfoxxed.me/quickshell/quickshell
upstream_ref: v0.3.1
build_depends:
  - qt6-base-dev
  - libvulkan-dev
cmake_flags:
  - -DCMAKE_BUILD_TYPE=Release
  - -DCRASH_HANDLER=OFF
build_suites:
  - trixie
  - sid
skip_suites:
  - bookworm
build_apt_sources:
  forky:
    - "deb http://deb.debian.org/debian forky main"
build_depends_suites:
  trixie:
    from: forky
    packages:
      - wayland-protocols
YAML

check "build_mode parses" \
    "$(yq eval '.build_mode // "binary"' "$TMP/source.yaml")" "source"
check "upstream_url parses" \
    "$(yq eval '.upstream_url // ""' "$TMP/source.yaml")" \
    "https://git.outfoxxed.me/quickshell/quickshell"
check "upstream_ref parses" \
    "$(yq eval '.upstream_ref // ""' "$TMP/source.yaml")" "v0.3.1"
check "build_depends joins to a space list" \
    "$(yq eval '((.build_depends // []) | join(" "))' "$TMP/source.yaml")" \
    "qt6-base-dev libvulkan-dev"
check "cmake_flags joins to a space list" \
    "$(yq eval '((.cmake_flags // []) | join(" "))' "$TMP/source.yaml")" \
    "-DCMAKE_BUILD_TYPE=Release -DCRASH_HANDLER=OFF"
check "build_suites joins to a space list" \
    "$(yq eval '((.build_suites // []) | join(" "))' "$TMP/source.yaml")" \
    "trixie sid"
check "skip_suites joins to a space list" \
    "$(yq eval '((.skip_suites // []) | join(" "))' "$TMP/source.yaml")" \
    "bookworm"

# Per-suite apt override (mirrors source-build.sh's lookups).
check "per-suite override 'from' parses (trixie)" \
    "$(yq eval '.build_depends_suites."trixie".from // ""' "$TMP/source.yaml")" "forky"
check "per-suite override packages join (trixie)" \
    "$(yq eval '((.build_depends_suites."trixie".packages // []) | join(" "))' "$TMP/source.yaml")" \
    "wayland-protocols"
check "suite without an override yields empty 'from'" \
    "$(yq eval '.build_depends_suites."forky".from // ""' "$TMP/source.yaml")" ""
check "apt source line for the override suite (forky)" \
    "$(yq eval '(.build_apt_sources."forky" // []) | .[]' "$TMP/source.yaml")" \
    "deb http://deb.debian.org/debian forky main"

# A binary config (no source keys) must default cleanly, not print "null".
cat > "$TMP/binary.yaml" <<'YAML'
package_name: eza
github_repo: eza-community/eza
artifact_format: tar.gz
YAML
check "binary config defaults build_mode" \
    "$(yq eval '.build_mode // "binary"' "$TMP/binary.yaml")" "binary"
check "binary config has empty build_depends" \
    "$(yq eval '((.build_depends // []) | join(" "))' "$TMP/binary.yaml")" ""
check "binary config has empty cmake_flags" \
    "$(yq eval '((.cmake_flags // []) | join(" "))' "$TMP/binary.yaml")" ""

echo
echo "Total: $TESTS_TOTAL, Failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
