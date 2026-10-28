#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./scripts/build-app.sh [options]
  --configuration release|debug  Build configuration (default: release)
  --arch arm64|x86_64             Build one architecture (default: current Mac)
  --version VERSION              Bundle version (default: 0.1.1)
  --output-dir DIRECTORY         Bundle destination (default: ./dist)
  --skip-build                   Package an already-built executable
  --sign IDENTITY                codesign identity (default: ad-hoc "-")
  --help                         Show this help

Creates Dockey.app without installing it. Requires Apple Command Line Tools and Swift 6+.
USAGE
}

configuration="release"
architecture=""
version="$DOCKEY_DEFAULT_VERSION"
output_dir="$DOCKEY_PROJECT_DIR/dist"
skip_build=false
signing_identity="-"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --configuration) [ "$#" -ge 2 ] || dockey_die "--configuration needs a value"; configuration="$2"; shift 2 ;;
        --arch) [ "$#" -ge 2 ] || dockey_die "--arch needs a value"; architecture="$2"; shift 2 ;;
        --version) [ "$#" -ge 2 ] || dockey_die "--version needs a value"; version="$2"; shift 2 ;;
        --output-dir) [ "$#" -ge 2 ] || dockey_die "--output-dir needs a value"; output_dir="$2"; shift 2 ;;
        --skip-build) skip_build=true; shift ;;
        --sign) [ "$#" -ge 2 ] || dockey_die "--sign needs a value"; signing_identity="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) dockey_die "unknown argument: $1" ;;
    esac
done
case "$configuration" in release|debug) ;; *) dockey_die "configuration must be release or debug" ;; esac
case "$architecture" in ""|arm64|x86_64) ;; *) dockey_die "architecture must be arm64 or x86_64" ;; esac
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || dockey_die "version must have the form 0.1.0"
dockey_require_macos
dockey_require_command swift
build_args=(-c "$configuration")
if [ -n "$architecture" ]; then build_args+=(--arch "$architecture"); fi
if ! $skip_build; then
    dockey_note "building $configuration executable"
    (cd "$DOCKEY_PROJECT_DIR" && swift build "${build_args[@]}" --product Dockey) >&2
fi
bin_dir="$(cd "$DOCKEY_PROJECT_DIR" && swift build "${build_args[@]}" --show-bin-path)"
[ -x "$bin_dir/Dockey" ] || dockey_die "built executable not found: $bin_dir/Dockey"
[ -d "$bin_dir/Dockey_Dockey.bundle" ] || dockey_die "SwiftPM resource bundle not found: $bin_dir/Dockey_Dockey.bundle"
output_dir="$(dockey_canonical_directory "$output_dir")"
target="$output_dir/Dockey.app"
dockey_validate_existing_target "$target"
if dockey_app_is_running "$target"; then dockey_die "quit this Dockey app before replacing it: $target"; fi
staging="$(mktemp -d "$output_dir/.dockey-build.XXXXXX")"
trap 'dockey_cleanup_staging "$staging" "$target"' EXIT
app="$staging/Dockey.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Dockey" "$app/Contents/MacOS/Dockey"
chmod 755 "$app/Contents/MacOS/Dockey"
ditto "$bin_dir/Dockey_Dockey.bundle" "$app/Contents/Resources/Dockey_Dockey.bundle"
if [ -f "$DOCKEY_PROJECT_DIR/Sources/Dockey/Resources/AppIcon.icns" ]; then
    cp "$DOCKEY_PROJECT_DIR/Sources/Dockey/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
fi
mkdir -p "$app/Contents/Resources/Licenses"
if [ -f "$DOCKEY_PROJECT_DIR/LICENSE" ]; then cp "$DOCKEY_PROJECT_DIR/LICENSE" "$app/Contents/Resources/Licenses/Apache-2.0.txt"; fi
if [ -f "$DOCKEY_PROJECT_DIR/THIRD_PARTY_NOTICES.md" ]; then cp "$DOCKEY_PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"; fi
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$DOCKEY_BUNDLE_ID</string>
  <key>CFBundleName</key><string>Dockey</string>
  <key>CFBundleDisplayName</key><string>Dockey</string>
  <key>CFBundleExecutable</key><string>Dockey</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
printf 'APPL????' > "$app/Contents/PkgInfo"
/usr/bin/plutil -lint "$app/Contents/Info.plist" >&2
sign_args=(--force --sign "$signing_identity")
if [ "$signing_identity" != "-" ]; then sign_args+=(--options runtime --timestamp); fi
/usr/bin/codesign "${sign_args[@]}" "$app" >&2
dockey_verify_signature "$app"
dockey_commit_app "$app" "$target" "$staging"
dockey_note "created $target"
if [ "$signing_identity" = "-" ]; then dockey_note "locally ad-hoc signed; not Developer ID signed or notarized"; fi
printf '%s\n' "$target"
