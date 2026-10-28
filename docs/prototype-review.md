# Prototype review

Reviewed locally in Chromium on 2026-10-28. These are browser design studies for a planned SwiftUI/AppKit app. Verification does not establish native accessibility, Docker integration, engine compatibility, signing, notarization, or live-container behavior.

## Completed checks

- Reviewed all three layouts in dark and light themes, plus settings and the icon gallery.
- Checked all three layouts at viewport widths 1440, 1024, 720, and 390px for document-level horizontal overflow. At narrow widths the inspector uses a focused detail view instead of nesting another vertical split.
- Verified individual container start/stop, group start/stop, pending action state, and aggregate counts using sample data.
- Verified search, unhealthy-state filtering, run-image sample creation, offline recovery, missing/empty scenarios, command search, keyboard shortcuts, and adjustable interface text.
- Opened every settings category. Checked the runtime resource impact preview and its cancellation path.
- Verified volume cleanup requires the exact sample volume name; Cancel closes the run form without submitting it.
- Verified comparison-page theme switching and direct-file prototype opening without the local server.
- Validated JavaScript syntax and parsed all 49 SVG exports as XML.
- Corrected issues found during review: narrow navigation overflow, small-screen inspector behavior, font-size specificity, form button defaults, container-name pattern syntax, and missing favicon requests.

## Product decisions still needed

- A (Grouped list) is selected. B and C remain comparison references.
- Choose the first native vertical slice. Recommended: connect to an existing local engine, show Compose groups, inspect a container, and stream logs.
- Set minimum macOS and hardware support, then check native controls and VoiceOver on that baseline.
- Validate the settings inventory against supported Colima/tool versions before making runtime controls editable.
- Dockey is the selected name. Set the repository owner, publication clearance, license, and release identity before publishing.

## Artifacts

Portable preview images are included under `prototypes/previews/`. Additional local QA captures live under ignored `output/playwright/`. The comparison page is `prototypes/compare.html` and the interactive study is `prototypes/index.html`.
