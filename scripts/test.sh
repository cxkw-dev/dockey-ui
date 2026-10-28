#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
dockey_require_macos
dockey_require_command swift
dockey_require_command swiftc

args=(test --disable-xctest)

# Some Command Line Tools releases ship the Swift Testing plugin in a nested
# directory that SwiftBuild does not discover automatically. Ask the selected
# compiler for its own resource directory; never assume an Xcode install path.
if resources="$(swiftc -print-target-info | /usr/bin/plutil -extract paths.runtimeResourcePath raw -o - -)"; then
    for plugin in "$resources/host/plugins/testing/libTestingMacros.dylib" "$resources/host/plugins/libTestingMacros.dylib"; do
        if [ -f "$plugin" ]; then
            args+=(-Xswiftc -load-plugin-library -Xswiftc "$plugin")
            break
        fi
    done
fi

cd "$DOCKEY_PROJECT_DIR"
exec swift "${args[@]}" "$@"
