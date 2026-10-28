# Verification record

Local validation on October 28, 2026, for the initial 0.1.0 native alpha.

## Environment

| Component | Tested |
| --- | --- |
| Host | Apple Silicon, macOS 26.7.1 |
| Build tools | Swift 6.4, Apple Command Line Tools |
| Docker CLI | Homebrew Docker 29.9.2 |
| Local runtime | Colima, Virtualization.framework |
| Engine | Docker Engine 29.5.2, aarch64 |
| Bundle | Release configuration, ad-hoc signed |

## Automated checks

`./scripts/check.sh` passed all **29 Swift Testing tests** and the disposable installation/archive checks. The Swift suite covers Compose-label grouping, local endpoint validation, argument validation, partial operation failures, redaction, UTF-8 log limits, concurrent pipe draining, process timeouts, sparse live log delivery, cancellation, context invalidation, and demo isolation.

Installer checks cover installation, replacement, dry runs, removal, refusal of unrelated or symbolic-link targets, ZIP extraction, and signature integrity. The final release app was also installed and removed at a separate temporary destination, then installed at the default per-user path. The release ZIP and SHA-256 were generated successfully.

## Real engine integration

`./scripts/smoke-docker.sh --context colima --report docs/verification/live-smoke.json` passed against the environment above. The [sanitized machine-readable result](verification/live-smoke.json) records discovery, Compose grouping, inspection, engine information, image/volume/network listings, stats, stop, start, restart, log tail, and cancellable log following.

Mutation tests targeted only a labelled disposable Alpine container with no mounts, ports, or network access. Existing container states and the global CLI context were compared before and after testing; they were unchanged. No test fixtures remained afterward. Private resource inventories were retained only in an ignored local directory.

## Installed native app

The release app was opened from the per-user Applications directory and connected to the real local engine. Native UI checks verified project grouping, search, real log following, redacted inspection, image inventory, and stop/start of a separate disposable fixture. Stop confirmation displayed the exact container name and selected context. The fixture was removed after testing.

Demo-mode UI checks verified individual lifecycle controls, stop confirmation, search, details, Settings, and appearance changes. [Dark](screenshots/dockey-dark.png) and [light](screenshots/dockey-light.png) screenshots were exported from the native release app using synthetic demo resources. They are interface evidence, not live-engine screenshots.

## Public source audit

Before the initial push, all intended tracked files were checked for credentials, private host paths, existing workload identifiers, executable SVG content, and unexpected file types. Fonts and their license notices were checked against their public sources; screenshots contain synthetic data. A separate agent reviewed publication and script safety.

The local detect-secrets 1.5.0 scan passed after auditing one false positive caused by the scanner package's version string inside the workflow. The scan rejected a separate synthetic credential candidate. CI repeats the tracked-file scan with network credential verification disabled. Ignored local inventories, build output, environment files, and signing material are excluded from publication. These checks reduce accidental disclosure risk; they do not guarantee detection of every possible secret.

## Compatibility limits

This is evidence for the listed local environment. The repository's CI separately tests and packages Apple Silicon and Intel builds; its public run results are available in [Actions](https://github.com/cxkw-dev/dockey-ui/actions). It does not establish live Docker compatibility across every macOS, engine, or runtime version. Release archives are ad-hoc signed, not Developer ID signed or notarized.
