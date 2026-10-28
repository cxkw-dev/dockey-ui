#!/bin/bash
# Exercises packaging boundaries with a disposable, locally signed fixture app.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
dockey_require_macos
dockey_require_command clang
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dockey-install-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
fixture="$test_root/source/Dockey.app"
destination="$test_root/Installed Apps"
mkdir -p "$fixture/Contents/MacOS" "$destination/Unrelated.app"
printf 'preserve me\n' > "$destination/Unrelated.app/sentinel"
cat > "$fixture/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.dockey.app</string>
<key>CFBundleExecutable</key><string>Dockey</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
</dict></plist>
PLIST
/usr/bin/clang -x c - -o "$fixture/Contents/MacOS/Dockey" <<'C'
int main(void) { return 0; }
C
/usr/bin/codesign --force --sign - "$fixture" >/dev/null 2>&1
"$DOCKEY_SCRIPT_DIR/install.sh" --app "$fixture" --destination "$destination" >/dev/null
[ -x "$destination/Dockey.app/Contents/MacOS/Dockey" ] || dockey_die "install test failed"
"$DOCKEY_SCRIPT_DIR/install.sh" --app "$fixture" --destination "$destination" >/dev/null
"$DOCKEY_SCRIPT_DIR/uninstall.sh" --app "$destination/Dockey.app" --dry-run >/dev/null
[ -d "$destination/Dockey.app" ] || dockey_die "dry run removed the app"
"$DOCKEY_SCRIPT_DIR/package-release.sh" --app "$destination/Dockey.app" --output-dir "$test_root/releases" >/dev/null
(cd "$test_root/releases" && /usr/bin/shasum -a 256 -c ./*.sha256) >/dev/null
mkdir -p "$test_root/expanded"
/usr/bin/ditto -x -k "$test_root/releases/"*.zip "$test_root/expanded"
dockey_validate_app "$test_root/expanded/Dockey.app"
dockey_verify_signature "$test_root/expanded/Dockey.app"
"$DOCKEY_SCRIPT_DIR/uninstall.sh" --app "$destination/Dockey.app" >/dev/null
[ ! -e "$destination/Dockey.app" ] || dockey_die "uninstall test failed"
[ -f "$destination/Unrelated.app/sentinel" ] || dockey_die "unrelated app changed"

mkdir -p "$destination/Dockey.app/Contents/MacOS"
cp "$fixture/Contents/MacOS/Dockey" "$destination/Dockey.app/Contents/MacOS/Dockey"
cp "$fixture/Contents/Info.plist" "$destination/Dockey.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier example.unrelated.app' "$destination/Dockey.app/Contents/Info.plist"
printf 'keep foreign bundle\n' > "$destination/Dockey.app/sentinel"
if "$DOCKEY_SCRIPT_DIR/install.sh" --app "$fixture" --destination "$destination" >/dev/null 2>&1; then dockey_die "installer accepted a foreign bundle"; fi
if "$DOCKEY_SCRIPT_DIR/uninstall.sh" --app "$destination/Dockey.app" >/dev/null 2>&1; then dockey_die "uninstaller accepted a foreign bundle"; fi
[ -f "$destination/Dockey.app/sentinel" ] || dockey_die "foreign bundle was removed"
rm -rf "$destination/Dockey.app"
ln -s "$fixture" "$destination/Dockey.app"
if "$DOCKEY_SCRIPT_DIR/install.sh" --app "$fixture" --destination "$destination" >/dev/null 2>&1; then dockey_die "installer accepted a symlink target"; fi
if "$DOCKEY_SCRIPT_DIR/uninstall.sh" --app "$destination/Dockey.app" >/dev/null 2>&1; then dockey_die "uninstaller accepted a symlink target"; fi
[ -d "$fixture" ] || dockey_die "symlink source was removed"
printf 'Installation checks passed: install, update, dry-run, exact uninstall, foreign/symlink refusal, archive checksum, and extracted signature.\n'
