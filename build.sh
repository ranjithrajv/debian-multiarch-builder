#!/bin/bash

# Wrapper script for backward compatibility
# Delegates to the modularized main script in src/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/src/main.sh" "$@"
