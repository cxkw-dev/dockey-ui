# Verification record

Local validation on October 28, 2026, for the native alpha, 0.1.2 service-icon update, and 0.1.3 AI Focus alignment. The first published alpha was 0.1.1; the unpublished 0.1.0 tag failed hosted Intel GUI validation.

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

The Swift suite contains **68 tests**, covering Compose-label grouping, local endpoint validation, argument validation, partial operation failures, redaction, UTF-8 log limits, concurrent pipe draining, process timeouts, persistent event/stats streams, cancellation, context invalidation, demo isolation, event-driven state coordination, and registry-specific service recognition. Focused regressions cover inspection/resource/log failures and retry, stale context responses, active-container filtering, resource changes during event gaps, draining event bursts while inventory is held, actual Docker image IDs, and credentials inside opaque labels/driver options. The local unit, resource-layout, and disposable installation/archive checks passed. Hosted CI repeats the complete suite for each architecture.

Installer checks cover installation, replacement, dry runs, removal, refusal of unrelated or symbolic-link targets, ZIP extraction, and signature integrity. The final release app was also installed and removed at a separate temporary destination, then installed at the default per-user path. The release ZIP and SHA-256 were generated successfully.

The copied-app launch check passed locally on Apple Silicon for both flat and wrapped resource-bundle layouts: re-signed copies missing one font or service mark were explicitly rejected, while each intact copy verified its bundled fonts, all themed vector marks, and license notices and exported a decodable demo PNG. Apple Silicon CI retains this full native gate. Intel CI explicitly verifies startup/resources and missing-font/mark rejection in both layouts without window/PNG rendering. Both modes catch resource lookup differences that compilation and signature checks alone cannot detect; only the full mode provides visual rendering evidence.

## Real engine integration

`./scripts/smoke-docker.sh --context colima --report docs/verification/live-smoke.json` passed against the environment above. The [sanitized machine-readable result](verification/live-smoke.json) records discovery, Compose grouping, inspection, engine information, image/volume/network listings, stats, stop, start, restart, a real lifecycle event stream, persistent metrics, log tail, and cancellable log following. Both new stream clients were explicitly cancelled after delivering the fixture's data.

Mutation tests targeted only a labelled disposable Alpine container with no mounts, ports, or network access. Existing container states and the global CLI context were compared before and after testing; they were unchanged. No test fixtures remained afterward. Private resource inventories were retained only in an ignored local directory.

## Installed native app

The release app was opened from the per-user Applications directory and connected to the real local engine. Native UI checks verified project grouping, search, real log following, redacted inspection, image inventory, and stop/start of a separate disposable fixture. Stop confirmation displayed the exact container name and selected context. The fixture was removed after testing.

Demo-mode UI checks verified individual lifecycle controls, stop confirmation, search, details, Settings, and appearance changes. [Dark](screenshots/dockey-dark.png) and [light](screenshots/dockey-light.png) screenshots were exported from the native release app using synthetic demo resources. They are interface evidence, not live-engine screenshots.

The modern state selector was checked with keyboard selection, and the custom checkbox exposed a native checked/unchecked accessibility value while updating the filtered list. Settings were checked in both appearances. The obsolete polling-interval setting was removed; [live updates](performance.md) describes the event stream, visible metrics, cache behavior, and measured CLI bottleneck.

The 0.1.2 failure views were also exercised in the installed app using an ignored, synthetic CLI fixture that cannot invoke Docker. Failed image loads showed an inline error and recovered through Retry. Failed inspection disabled JSON copying and kept Mounts in an explicit error state; successful retry then showed the genuine empty-mount result. Interrupted logs showed a separate error and truthful footer, then recovered through Retry. Switching detail tabs preserved the same log process. Dockey's original executable preference and Colima connection were restored, and no synthetic CLI children remained. These are UI failure-state checks, not live-engine mutation tests; their captures are excluded from public documentation.

An additional fixture was created outside the running app, appeared automatically, and changed to stopped after an external CLI stop, without choosing Refresh. The fixture was removed afterward. This verifies native event-driven updates in addition to the Core stream integration probe. The app also contains the larger matte Dock icon and borderless toolbar context selector.

The current icons cover seven service families: official monochrome ClickHouse, Langfuse, and Temporal marks; the official standalone MongoDB leaf; AI Focus's existing F; original Redis cache lines; and a full-body Lucide Lab elephant for PostgreSQL. The elephant is ISC-licensed, with unchanged path geometry, theme gray, and a documented compact stroke adjustment. A generic cube handles unrecognized images. SVG sources and offline-generated native vector PDFs retain provenance, hashes, and complete upstream license notices. The shared icon slot uses adjusted drawing sizes to balance solid marks, outlines, and narrow shapes. See [service sources and recognition limits](service-icons.md); these identifiers are presentation hints, not image-authenticity or vendor-approval checks.

## Public source audit

Before the initial push, all intended tracked files were checked for credentials, private host paths, existing workload identifiers, executable SVG content, and unexpected file types. Fonts and their license notices were checked against their public sources; screenshots contain synthetic data. A separate agent reviewed publication and script safety.

The local detect-secrets 1.5.0 scan passed after auditing one false positive caused by the scanner package's version string inside the workflow. The scan rejected a separate synthetic credential candidate. CI repeats the tracked-file scan with network credential verification disabled. Ignored local inventories, build output, environment files, and signing material are excluded from publication. These checks reduce accidental disclosure risk; they do not guarantee detection of every possible secret.

The service-icon update also records exact public upstream commit IDs and verified asset SHA-256 values as audited scanner false positives. No file or path exclusions were added for these manifests. SVGs were checked for active or external content; PDF renderings were checked for actions, embedded data, raster replacements, and private path metadata. Bundled files and license texts match their recorded hashes and source copies.

## Compatibility limits

The initial hosted Intel GUI check aborted after successful font verification with Metal's `Target device architecture is nil` assertion in `MTLLoader`. Both architectures' 54 Swift tests passed in that run, and Apple Silicon passed the native PNG checks; this does not establish Intel GUI compatibility. The workflow now records `system_profiler SPDisplaysDataType` diagnostics on Intel and explicitly selects `--resources-only` there. Both layouts still require missing-font rejection and intact startup/font/license verification. Apple Silicon still requires demo PNG rendering. There is no automatic fallback and no suppression of unexpected failures. **Physical Intel visual compatibility remains unverified.**

As an additional check, the CI-built 0.1.2 `x86_64` archive from [the successful main run](https://github.com/cxkw-dev/dockey-ui/actions/runs/40773454256) was downloaded, checksum-checked, extracted, and signature-verified locally. Its full native launch check passed for both resource layouts under the already installed Rosetta on Apple Silicon, including missing-resource rejection and decodable demo PNGs. This verifies a translated Intel build on this host, not graphical behavior on physical Intel hardware.

This is evidence for the listed local environment. The repository's CI separately tests and packages Apple Silicon and Intel builds; its public run results are available in [Actions](https://github.com/cxkw-dev/dockey-ui/actions). It does not establish live Docker compatibility across every macOS, engine, or runtime version. Release archives are ad-hoc signed, not Developer ID signed or notarized.
