#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./scripts/package-release.sh [--app PATH] [--output-dir DIRECTORY]
Creates a ZIP containing Dockey.app and a portable SHA-256 checksum file.
Defaults: ./dist/Dockey.app and ./dist. Does not publish a release.
USAGE
}
app="$DOCKEY_PROJECT_DIR/dist/Dockey.app"
output_dir="$DOCKEY_PROJECT_DIR/dist"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --app) [ "$#" -ge 2 ] || dockey_die "--app needs a value"; app="$2"; shift 2 ;;
        --output-dir) [ "$#" -ge 2 ] || dockey_die "--output-dir needs a value"; output_dir="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) dockey_die "unknown argument: $1" ;;
    esac
done
dockey_require_macos
dockey_validate_app "$app"
dockey_verify_signature "$app"
version="$(dockey_plist_value "$app" CFBundleShortVersionString)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || dockey_die "unexpected bundle version: $version"
architecture="$(/usr/bin/lipo -archs "$app/Contents/MacOS/Dockey")"
case "$architecture" in arm64|x86_64) ;; *arm64*x86_64*|*x86_64*arm64*) architecture="universal" ;; *) dockey_die "unexpected executable architecture: $architecture" ;; esac
output_dir="$(dockey_canonical_directory "$output_dir")"
name="Dockey-$version-macos-$architecture.zip"
staging="$(mktemp -d "$output_dir/.dockey-release.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$staging/$name"
(cd "$staging" && /usr/bin/shasum -a 256 "$name" > "$name.sha256")
mv "$staging/$name" "$output_dir/$name"
mv "$staging/$name.sha256" "$output_dir/$name.sha256"
dockey_note "archive signature is inherited from the app; notarization is a separate step"
printf '%s\n' "$output_dir/$name" "$output_dir/$name.sha256"
