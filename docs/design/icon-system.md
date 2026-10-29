# Icon system

Original geometric SVG artwork, created for this container management interface. The icon gallery is `design/prototypes/icons.html`. Individual SVG source files are in `design/icons/`.

- Master coordinate system: 20 × 20, normally with a 2px safe inset.
- Stroke: 1.45px, rounded caps and joins, inherited foreground color.
- Primary rendered sizes: 16px in table controls, 20px in navigation, 24–28px for selected resource identity.
- Shapes: consistent cuboid/container, stacked project layers, cylindrical storage, network branches, processor and memory hardware, and restrained lifecycle controls.
- Icons accompany accessible labels or tooltips; state is also expressed in text. Small glyphs retain larger hit targets.
- Resource and navigation icons remain neutral. Semantic color is reserved for active selection, status, focus, and destructive actions.
- No third-party logo, emoji, icon font, or external icon service is used.

The prototype source of truth is the path dictionary in `design/prototypes/icons.js`. The SVG exports preserve those paths and `currentColor`. For the native app, validate optical weight against actual control sizes, convert to template vector assets as appropriate, and expose labels through SwiftUI/AppKit accessibility APIs.

Artwork source is included for review. Final repository licensing will be chosen before publication.
