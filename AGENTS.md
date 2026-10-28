# Repository guidance

## Build and verify

- `./scripts/check.sh` runs unit and disposable installation tests.
- `./scripts/build-app.sh` builds and ad-hoc signs the native app using SwiftPM.
- `./scripts/smoke-docker.sh --context LOCAL_CONTEXT` opts into a real-engine test using one explicitly labelled disposable fixture. Never use existing user containers for mutation tests.
- Documentation screenshots must use native `--demo` mode. Never publish real resource names, logs, host configuration, or credentials.

## Architecture

- Keep Docker parsing, models, subprocess execution, and safety contracts in `DockeyCore`.
- Keep state and lifecycle coordination in `Sources/Dockey/State`, with native views in `Views` and shared styling in `Design`.
- Pass a selected, verified local context to every engine command. Do not switch global Docker contexts or expose arbitrary shell execution.
- Use argument arrays, bounded output, timeouts, cancellation, and per-container operation results.
- Preserve Compose ownership from labels; app grouping must not infer ownership from container names.
- Keep app preferences distinct from engine and project configuration. Unsupported capabilities should not appear as working controls.

## Data and publication

- Do not prune or remove engine data, uninstall runtimes, or alter unrelated services.
- Installer/uninstaller changes must retain exact bundle identity checks and per-user ownership boundaries.
- Keep source install and release-signing limitations accurate in the README and install guide.
- Use plain human-style commits, branches, and PR text, without generated-by branding or coauthor trailers.
