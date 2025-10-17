#!/bin/bash

# Utility functions for logging and output formatting

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Error reporting function
error() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}" >&2
}

info() {
    echo -e "${BLUE}ℹ️  INFO: $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}
