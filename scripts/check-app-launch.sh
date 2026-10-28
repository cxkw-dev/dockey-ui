#!/bin/bash
# Exercise a copied, signed .app in demo mode; never connect to a real engine.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./scripts/check-app-launch.sh [--app PATH] [--timeout SECONDS] [--resources-only]
Defaults: ./dist/Dockey.app and a 30-second limit for each launch.

Copies the app into an isolated temporary location and tests both flat SwiftPM
and wrapped SwiftBuild resource bundles. Each shape must reject a missing font
and verify that the intact app can launch and export a valid PNG.
Requires a macOS graphical session and Python 3 for the full default check.
--resources-only explicitly skips GUI rendering and PNG export; both layouts
still verify startup, fonts/licenses, and missing-font rejection. No auto fallback.
Uses demo data only.
USAGE
}
app="$DOCKEY_PROJECT_DIR/dist/Dockey.app"
timeout_seconds=30
resources_only=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --app) [ "$#" -ge 2 ] || dockey_die "--app needs a value"; app="$2"; shift 2 ;;
        --timeout) [ "$#" -ge 2 ] || dockey_die "--timeout needs a value"; timeout_seconds="$2"; shift 2 ;;
        --resources-only) resources_only=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) dockey_die "unknown argument: $1" ;;
    esac
done
[[ "$timeout_seconds" =~ ^[0-9]+$ ]] || dockey_die "timeout must be an integer"
[ "$timeout_seconds" -ge 1 ] && [ "$timeout_seconds" -le 180 ] || dockey_die "timeout must be between 1 and 180 seconds"
dockey_require_macos
dockey_require_command python3
dockey_validate_app "$app"
dockey_verify_signature "$app"
app="$(cd "$(dirname "$app")" && pwd -P)/Dockey.app"
arguments=("$app" "$timeout_seconds")
if [ "$resources_only" = true ]; then arguments+=(--resources-only); fi
exec python3 "$DOCKEY_SCRIPT_DIR/lib/check_app_launch.py" "${arguments[@]}"
