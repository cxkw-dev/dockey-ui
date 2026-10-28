#!/bin/bash
# Shared packaging constants and exact-path safety checks. Compatible with macOS Bash 3.2.

DOCKEY_NAME="Dockey"
DOCKEY_BUNDLE_ID="dev.dockey.app"
DOCKEY_DEFAULT_VERSION="0.1.3"
DOCKEY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DOCKEY_PROJECT_DIR="$(cd "$DOCKEY_SCRIPT_DIR/.." && pwd -P)"

dockey_die() { printf 'Dockey: %s\n' "$*" >&2; exit 1; }
dockey_note() { printf 'Dockey: %s\n' "$*" >&2; }
dockey_require_macos() { [ "$(uname -s)" = "Darwin" ] || dockey_die "this script requires macOS."; }
dockey_require_command() { command -v "$1" >/dev/null 2>&1 || dockey_die "required command not found: $1"; }

dockey_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null
}

dockey_validate_app() {
    local candidate="$1"
    [ ! -L "$candidate" ] || dockey_die "refusing a symbolic-link app path: $candidate"
    [ -d "$candidate" ] || dockey_die "app does not exist: $candidate"
    [ "$(basename "$candidate")" = "Dockey.app" ] || dockey_die "expected a Dockey.app bundle: $candidate"
    [ "$(dockey_plist_value "$candidate" CFBundleIdentifier)" = "$DOCKEY_BUNDLE_ID" ] || dockey_die "bundle identifier is not $DOCKEY_BUNDLE_ID: $candidate"
    [ -x "$candidate/Contents/MacOS/Dockey" ] || dockey_die "app executable is missing: $candidate"
}

dockey_validate_existing_target() {
    local candidate="$1"
    if [ -e "$candidate" ] || [ -L "$candidate" ]; then
        dockey_validate_app "$candidate"
    fi
}

dockey_app_is_running() {
    # Inspect only the executable in the exact target bundle, not every process with this name.
    /bin/ps -axo command= | /usr/bin/awk -v target="$1/Contents/MacOS/Dockey" '
      $0 == target || index($0, target " ") == 1 { found = 1 }
      END { exit !found }
    '
}

dockey_verify_signature() {
    /usr/bin/codesign --verify --deep --strict "$1" 2>/dev/null || dockey_die "app signature verification failed: $1"
}

dockey_canonical_directory() {
    [ ! -L "$1" ] || dockey_die "refusing a symbolic-link destination directory: $1"
    mkdir -p "$1"
    (cd "$1" && pwd -P)
}

dockey_commit_app() {
    local staged_app="$1" target="$2" staging="$3"
    mkdir -p "$staging/previous"
    if [ -d "$target" ]; then mv "$target" "$staging/previous/Dockey.app"; fi
    if ! mv "$staged_app" "$target"; then
        if [ -d "$staging/previous/Dockey.app" ]; then mv "$staging/previous/Dockey.app" "$target"; fi
        dockey_die "could not replace the app; the previous copy was restored"
    fi
}

dockey_cleanup_staging() {
    local cleanup_status="$?" staging="$1" target="$2"
    if [ -d "$staging/previous/Dockey.app" ] && [ ! -e "$target" ]; then
        mv "$staging/previous/Dockey.app" "$target"
    fi
    rm -rf "$staging"
    return "$cleanup_status"
}
