#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./scripts/uninstall.sh [options]
  --app PATH     App to remove (default: ~/Applications/Dockey.app)
  --purge        Also remove only Dockey preferences and Application Support/Dockey
  --dry-run      Show exact removal targets without deleting anything
  --help         Show this help

Quit Dockey first with Command-Q, menu bar > Quit Dockey, or Dock > Quit.
The red window close button only hides it. This never uninstalls Docker/Colima
or removes engine resources.
USAGE
}
app="$HOME/Applications/Dockey.app"
purge=false
dry_run=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --app) [ "$#" -ge 2 ] || dockey_die "--app needs a value"; app="$2"; shift 2 ;;
        --purge) purge=true; shift ;;
        --dry-run) dry_run=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) dockey_die "unknown argument: $1" ;;
    esac
done
dockey_require_macos
[ "$(basename "$app")" = "Dockey.app" ] || dockey_die "expected an exact Dockey.app path"
[ ! -L "$app" ] || dockey_die "refusing a symbolic-link app path: $app"
support="$HOME/Library/Application Support/Dockey"
if $purge; then [ ! -L "$support" ] || dockey_die "refusing a symbolic-link Application Support directory: $support"; fi
if [ -e "$app" ]; then
    dockey_validate_app "$app"
    app="$(cd "$(dirname "$app")" && pwd -P)/Dockey.app"
    if dockey_app_is_running "$app"; then dockey_die "quit Dockey with Command-Q, menu bar > Quit Dockey, or Dock > Quit before uninstalling (closing the window only hides it): $app"; fi
    printf 'Remove app: %s\n' "$app"
    if ! $dry_run; then rm -rf "$app"; fi
else
    dockey_note "app is already absent: $app"
fi
if $purge; then
    printf 'Remove preferences domain: %s\n' "$DOCKEY_BUNDLE_ID"
    printf 'Remove app support: %s\n' "$support"
    if ! $dry_run; then
        /usr/bin/defaults delete "$DOCKEY_BUNDLE_ID" 2>/dev/null || true
        if [ -d "$support" ]; then rm -rf "$support"; fi
    fi
fi
dockey_note "Docker/Colima installations, contexts, containers, images, networks, and volumes are untouched"
if $dry_run; then dockey_note "dry run; nothing removed"; fi
