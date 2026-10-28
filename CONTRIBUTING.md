# Contributing to Dockey

Start with [the architecture](docs/architecture.md) and the [product brief](docs/product-brief.md). The selected interface is the grouped-list design. Browser prototypes are retained as design references; native app behavior is the implementation to test.

## Local work

Use macOS 14+ and Swift 6+. Clone the repository, then run:

```sh
./scripts/check.sh
./scripts/build-app.sh
open dist/Dockey.app --args --demo
```

Use demo mode while changing UI. If you test against a live engine, keep the selected context explicit and use only disposable resources you created. Never prune a developer's engine, stop existing project services, delete a VM, or remove volumes as a testing shortcut.

For a focused Swift test run, use `./scripts/test.sh --filter DockerParsingTests`. The wrapper disables XCTest discovery and loads the selected toolchain's Swift Testing macro plugin when necessary, allowing the same suite to work with full Xcode and Command Line Tools. Pass other `swift test` options through this wrapper rather than hardcoding a toolchain path.

## Code expectations

- Keep views focused on presentation and core logic independently testable.
- Use typed, Sendable models and structured concurrency. Own cancellation and process lifetime explicitly.
- Execute tools through argument arrays and validated executable paths; no interpolated shell commands.
- Treat Compose labels as ownership metadata. Do not infer ownership from names.
- Preserve partial operation results and show actionable failures.
- Add meaningful tests for new parsing, operation semantics, cancellation, or security boundaries. Avoid tests that only repeat implementation details.
- Review light/dark appearance, keyboard focus, resizing, and long names when changing UI.
- Keep user data and credentials out of fixtures, screenshots, issue reports, and logs.

## Pull requests

Describe the concrete problem and resulting behavior, plus the verification you ran. For UI work, include native screenshots made with demo data. For Docker operations, explain the selected context, affected resources, failure behavior, and cancellation.

The app deliberately separates its preferences from runtime and container/project configuration. Discuss changes that expand privileges, introduce deletion, execute project files, add remote endpoints, or require a persistent helper before building a new workflow around them.

## Releases

`build-app.sh` and `package-release.sh` create local bundles and checksums. They do not publish anything. Before tagging, pass the checks on `main`, complete native app validation, and add `docs/releases/vVERSION.md` describing the actual scope, architecture support, signing/notarization status, and known limitations.

Pushing a `vMAJOR.MINOR.PATCH` tag triggers CI builds for Apple Silicon and Intel. The tag-only release job waits for both, verifies every archive against its checksum, and publishes a prerelease using the checked-in notes. Only that job receives `contents: write`; build/test jobs remain read-only. A failed or incomplete architecture build cannot publish a release, and existing releases are not silently overwritten on a workflow rerun.

Never put developer certificates, private keys, access tokens, or notarization credentials in the repository. The publishing job uses GitHub's ephemeral built-in token and does not require a personal access token.

Before publishing changes, stage only the intended public files and run `./scripts/check-secrets.sh`. It uses detect-secrets 1.5.0 (or runs that pinned version through `uvx`) against tracked files, without network verification of candidate credentials. CI repeats this check. The `.secrets.baseline` records scanner settings and individually audited false positives; it must never be used to accept real credentials. Review new findings individually. A passing scanner does not replace checking screenshots, logs, resource names, file paths, and history for private data.

Contributions are submitted under the [Apache-2.0 license](LICENSE). Keep third-party notices and original font licenses with redistributed assets.
