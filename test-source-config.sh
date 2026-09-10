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

# --- package.yaml parsing (mirrors config.sh) -----------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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
