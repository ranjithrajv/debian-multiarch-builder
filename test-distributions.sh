#!/bin/bash

# Test script for per-suite base images and architecture allowlists.
# Covers the Ubuntu support added to data/system.yaml: which base image a
# suite builds on, which architectures it admits, and which suites the EOL
# filter drops.

set -e

# config.sh sources "$SCRIPT_DIR/data/yaml-utils.sh" and calls info()/warning()
# from logging.sh, both of which main.sh normally sets up before sourcing it.
# Replicate that here since this script sources it directly.
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/src" && pwd)"
source src/lib/logging.sh
source src/lib/config.sh

fails=0

check() {  # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "  ok    $1"
    else
        echo "  FAIL  $1: expected '$2', got '$3'"
        fails=$((fails + 1))
    fi
}

arch_check() {  # arch_check <arch> <dist> <yes|no>
    local got="no"
    is_arch_supported_for_dist "$1" "$2" && got="yes"
    check "$1 on $2" "$3" "$got"
}

echo "base_image_for:"
check "debian suite falls back to debian:<suite>" "debian:trixie" "$(base_image_for trixie)"
check "sid too"                                  "debian:sid"    "$(base_image_for sid)"
check "ubuntu suite uses its base_image"         "ubuntu:noble"  "$(base_image_for noble)"
check "unknown suite still yields something"     "debian:nosuch" "$(base_image_for nosuch)"

echo "is_arch_supported_for_dist:"
arch_check amd64   noble    yes
arch_check riscv64 noble    yes
arch_check i386    noble    no   # dropped as a full Ubuntu port after 18.04
arch_check armel   noble    no   # never an Ubuntu port
arch_check loong64 noble    no   # never an Ubuntu port
arch_check i386    bookworm yes  # Debian rules untouched by the allowlist
arch_check loong64 sid      yes

echo "filter_expired_distributions:"
check "expired suites dropped, live ones kept" \
    "bookworm trixie noble" \
    "$(filter_expired_distributions "bullseye bookworm trixie questing noble" 2>/dev/null)"

echo
if [ "$fails" -eq 0 ]; then
    echo "All checks passed."
else
    echo "$fails check(s) failed."
    exit 1
fi
