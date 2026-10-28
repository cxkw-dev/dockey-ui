#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./scripts/install.sh [options]
  --app PATH              Install an existing Dockey.app instead of building
  --destination DIRECTORY Installation directory (default: ~/Applications)
  --open                  Open the installed app
  --help                  Show this help

No sudo is needed for the default per-user installation. Quit Dockey before updating it.
USAGE
}
source_app=""
destination="$HOME/Applications"
open_after=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --app) [ "$#" -ge 2 ] || dockey_die "--app needs a value"; source_app="$2"; shift 2 ;;
        --destination) [ "$#" -ge 2 ] || dockey_die "--destination needs a value"; destination="$2"; shift 2 ;;
        --open) open_after=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) dockey_die "unknown argument: $1" ;;
    esac
done
dockey_require_macos
if [ -z "$source_app" ]; then source_app="$("$DOCKEY_SCRIPT_DIR/build-app.sh")"; fi
dockey_validate_app "$source_app"
source_app="$(cd "$(dirname "$source_app")" && pwd -P)/Dockey.app"
dockey_verify_signature "$source_app"
destination="$(dockey_canonical_directory "$destination")"
target="$destination/Dockey.app"
[ "$source_app" != "$target" ] || dockey_die "source and destination are the same app"
dockey_validate_existing_target "$target"
if dockey_app_is_running "$target"; then dockey_die "quit Dockey before updating: $target"; fi
staging="$(mktemp -d "$destination/.dockey-install.XXXXXX")"
trap 'dockey_cleanup_staging "$staging" "$target"' EXIT
ditto "$source_app" "$staging/Dockey.app"
dockey_validate_app "$staging/Dockey.app"
dockey_verify_signature "$staging/Dockey.app"
dockey_commit_app "$staging/Dockey.app" "$target" "$staging"
dockey_note "installed $target"
dockey_note "Docker, Colima, containers, images, volumes, and CLI context were not changed"
if $open_after; then /usr/bin/open "$target"; fi
printf '%s\n' "$target"
