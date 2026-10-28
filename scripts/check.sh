#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
dockey_require_macos
for script in "$DOCKEY_SCRIPT_DIR/"*.sh "$DOCKEY_SCRIPT_DIR/lib/"*.sh; do bash -n "$script"; done
python3 "$DOCKEY_SCRIPT_DIR/test-resource-layouts.py"
"$DOCKEY_SCRIPT_DIR/test-installation.sh"
"$DOCKEY_SCRIPT_DIR/test.sh"
