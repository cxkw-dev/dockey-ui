#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
dockey_require_macos
skip_build=false
case "${1:-}" in
    "") ;;
    --skip-build) skip_build=true; shift ;;
    --help|-h) printf '%s\n' 'Usage: ./scripts/generate-app-icon.sh [--skip-build]'; exit 0 ;;
    *) dockey_die "usage: ./scripts/generate-app-icon.sh [--skip-build]" ;;
esac
[ "$#" -eq 0 ] || dockey_die "usage: ./scripts/generate-app-icon.sh [--skip-build]"
for icon_tool in swift sips iconutil; do dockey_require_command "$icon_tool"; done
if ! $skip_build; then
    (cd "$DOCKEY_PROJECT_DIR" && swift build -c release --product Dockey) >&2
fi
bin_dir="$(cd "$DOCKEY_PROJECT_DIR" && swift build -c release --show-bin-path)"
executable="$bin_dir/Dockey"
[ -x "$executable" ] || dockey_die "build the release executable before --skip-build"
source_png="$DOCKEY_PROJECT_DIR/design-assets/dockey-dock-icon.png"
"$executable" --render-icon "$source_png"
staging="$(mktemp -d "${TMPDIR:-/tmp}/dockey-icon.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
iconset="$staging/Dockey.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    retina=$((size * 2))
    sips -z "$size" "$size" "$source_png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$retina" "$retina" "$source_png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns --output "$DOCKEY_PROJECT_DIR/Sources/Dockey/Resources/AppIcon.icns" "$iconset"
dockey_note "generated Dock PNG and all canonical ICNS sizes"
