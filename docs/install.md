# Install, update, and remove Dockey

## Requirements

- macOS 14 or later, Apple Silicon or Intel.
- An existing local Docker Engine connection and Docker CLI. Colima is the first runtime used for live development verification.
- For source builds: Swift 6 or later and the macOS SDK, provided by Apple's Command Line Tools or Xcode. Full Xcode is not required by the packaging scripts.

Check your tools:

```sh
swift --version
docker context ls
docker --context YOUR_LOCAL_CONTEXT info
```

If developer tools are absent, run `xcode-select --install`, complete Apple's installer, then check the Swift version. Dockey does not download developer tools or a container runtime automatically.

## Build and install from source

```sh
git clone https://github.com/cxkw-dev/dockey-ui.git
cd dockey-ui
./scripts/install.sh --open
```

The default destination is `~/Applications/Dockey.app`. The script builds a release executable, adds the SwiftPM resources and application metadata, ad-hoc signs the result, verifies the app signature, and copies it to a per-user Applications folder. No administrator access is required.

Build without installing:

```sh
./scripts/build-app.sh
open dist/Dockey.app
```

Choose a destination or an already-built app:

```sh
./scripts/install.sh --app dist/Dockey.app --destination ~/Applications --open
```

The destination is a directory; the final app is always named `Dockey.app`. The scripts refuse to overwrite a symlink, a non-Dockey bundle, or an app running from that exact target path. Quit the installed copy before updating it.

## Release ZIPs and Gatekeeper

[Release assets](https://github.com/cxkw-dev/dockey-ui/releases) are named `Dockey-VERSION-macos-arm64.zip` or `Dockey-VERSION-macos-x86_64.zip`; a universal archive is named accordingly if one is produced. Choose `arm64` for Apple Silicon or `x86_64` for Intel. Each archive includes the complete `.app`; keep its resources inside the bundle.

Download both the ZIP and its matching `.sha256` file into the same folder and verify before extracting:

```sh
shasum -a 256 -c Dockey-0.1.0-macos-arm64.zip.sha256
```

Extract the archive and move `Dockey.app` to `~/Applications` or your normal Applications folder. The script can also install the extracted app using `--app`.

An ad-hoc signature checks bundle integrity but does not identify a Developer ID publisher or establish notarization. These initial builds are not notarized. macOS may block a quarantined downloaded build. Build locally from reviewed source, or use Apple's documented Privacy & Security approval flow only after deciding to trust the downloaded app. Do not disable Gatekeeper globally. See [Apple's guidance on opening apps safely](https://support.apple.com/en-us/102445).

## Connect to your engine

Dockey uses an app-selected context on every engine request. It does not run `docker context use`, modify Docker's configuration, or alter global context selection. Only local Unix-socket endpoints are accepted in the initial release.

If the CLI is not detected, open **Settings → Connections** and choose the installed Docker executable. Common Homebrew paths are `/opt/homebrew/bin/docker` and `/usr/local/bin/docker`. Choosing an executable changes only Dockey's preference.

Quitting or uninstalling Dockey leaves the engine and existing containers running. Opening the app does not start Colima, create containers, or apply a Compose project.

## Update

1. Quit Dockey.
2. Review the new source or release notes.
3. Install the new build using the same command or replace the app in Finder.

Preferences are retained. The initial release has no automatic updater; nothing downloads or replaces the app in the background.

## Uninstall

Quit the app, then move its exact `.app` bundle to the Trash. Preferences can remain if you plan to reinstall.

The repository includes an exact-path uninstaller:

```sh
./scripts/uninstall.sh --dry-run
./scripts/uninstall.sh
```

If installed elsewhere, identify that copy explicitly:

```sh
./scripts/uninstall.sh --app /Applications/Dockey.app --dry-run
./scripts/uninstall.sh --app /Applications/Dockey.app
```

The script validates `CFBundleIdentifier=dev.dockey.app` before deleting an existing app. It refuses symbolic-link app paths and does not discover or remove other copies on your behalf.

Optional preference removal:

```sh
./scripts/uninstall.sh --purge --dry-run
./scripts/uninstall.sh --purge
```

`--purge` adds exactly the `dev.dockey.app` preferences domain and `~/Library/Application Support/Dockey`. It does not erase other application preferences. The app must be closed so it cannot write preferences back while they are being removed.

**Engine scope:** these operations never uninstall Docker or Colima, delete a VM, change Docker contexts, prune images, remove containers, delete volumes, or modify Compose project directories.

## Produce a distributable archive

```sh
./scripts/build-app.sh --version 0.1.0
./scripts/package-release.sh
```

To build a single non-default architecture, pass `--arch arm64` or `--arch x86_64` to `build-app.sh`. The archive name is derived from the actual Mach-O executable, not a manually supplied label.

The CI version-tag workflow builds and tests both architectures before a separate publishing job verifies the checksums and creates a prerelease. Add `docs/releases/vVERSION.md` before pushing a version tag. This does not change the signing status of the artifacts.

For an established Developer ID release, build with `--sign "Developer ID Application: ..."`, then submit the archive to Apple's notary service and staple the approved ticket before publication. The script enables hardened runtime and timestamping for a real identity; it does not create certificates, access a developer account, or claim notarization. Configure credentials outside the repository, and reverify the final app and checksum after any signing/stapling change. [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) describes the required account setup and commands.
