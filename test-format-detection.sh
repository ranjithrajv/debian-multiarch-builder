#!/bin/bash

# Test script for artifact format detection and extraction.
# Guards against regressing tar.gz/tgz/zip support while adding
# tar.xz/tar.bz2/tar.zst (discovery.sh's detect_artifact_format, and the
# auto-detecting `tar -tf`/`tar -xf` extraction it feeds in build.sh).

set -e

export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/src" && pwd)"
source src/lib/logging.sh
source src/lib/discovery.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_TOTAL=0
TESTS_FAILED=0

check_format() {
    local filename="$1" expected="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    local got
    got="$(detect_artifact_format "$filename")"
    if [ "$got" = "$expected" ]; then
        echo -e "${GREEN}✅ PASS${NC}: $filename -> $got"
    else
        echo -e "${RED}❌ FAIL${NC}: $filename -> $got (expected $expected)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

check_format "tool-linux-amd64.zip" "zip"
check_format "tool-linux-amd64.tar.gz" "tar.gz"
check_format "tool-linux-amd64.tgz" "tgz"
check_format "helix-25.07.1-x86_64-linux.tar.xz" "tar.xz"
check_format "tool-linux-amd64.tar.bz2" "tar.bz2"
check_format "tool-linux-amd64.tar.zst" "tar.zst"

# Auto-detecting extraction (build.sh's `tar -tf`/`tar -xf`, no -z/-J) must
# round-trip every compressed tar variant, not just gzip.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/src/fakebin" && echo "fake" > "$TMP/src/fakebin/tool"
for pair in "tar.gz:z" "tar.xz:J" "tar.bz2:j"; do
    ext="${pair%%:*}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    archive="$TMP/asset.$ext"
    (cd "$TMP/src" && tar "-c${pair#*:}f" "$archive" fakebin)
    out="$TMP/out-$ext"; mkdir -p "$out"
    if tar -tf "$archive" >/dev/null 2>&1 && tar -xf "$archive" -C "$out" 2>/dev/null \
        && [ -f "$out/fakebin/tool" ]; then
        echo -e "${GREEN}✅ PASS${NC}: auto-detect extraction round-trips .$ext"
    else
        echo -e "${RED}❌ FAIL${NC}: auto-detect extraction failed for .$ext"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

echo
echo "Total: $TESTS_TOTAL, Failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
