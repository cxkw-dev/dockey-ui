#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
cd "$DOCKEY_PROJECT_DIR"

# Scan tracked files locally; never verify candidate credentials over the network.
if command -v detect-secrets-hook >/dev/null 2>&1; then
    scanner=(detect-secrets-hook)
elif command -v uvx >/dev/null 2>&1; then
    scanner=(uvx --from detect-secrets==1.5.0 detect-secrets-hook)
else
    dockey_die "install detect-secrets 1.5.0 or uv, then rerun this check"
fi
git ls-files -z | xargs -0 "${scanner[@]}" --no-verify --baseline .secrets.baseline
