# Dockey

Product name: **Dockey**. Selected layout: **A — Grouped list**.

## Wordmark

Use **Geist Sans Semibold (600)** with -0.04em letter spacing. This keeps the wordmark aligned with the Vercel-inspired interface, while the heavier weight, compact spacing, and mascot provide the brand identity. Use weight 500 for the small window title and preserve the wordmark as selectable text.

The typeface is bundled locally in `prototypes/assets/fonts/`, with its SIL Open Font License in `Geist-OFL.txt`. Source: [Vercel Geist](https://vercel.com/font).

Geist Sans is shared across the wordmark and interface. Geist Mono remains the typeface for logs and technical values.

## Mark

The mark is a flat, charcoal puff with large off-white eyes, two tiny feet, and a small teal shipping container. It follows the requested soot-sprite-inspired direction using simple filled shapes. There are no gradients, textures, highlights, shadows, or raster images in the final mark.

Source: `design-assets/dockey-mark.svg`. The identical prototype export is `prototypes/assets/dockey-mark.svg`. Preview the mark on light and dark surfaces and at small sizes in `prototypes/brand.html`.

Keep the mark small beside the name in the sidebar. A larger version can appear in About and the empty state. Resource icons and lifecycle controls retain the existing restrained SVG icon system.

The macOS Dock icon uses a matte charcoal tile and a larger mascot, with a brighter teal rim and halo that remain visible at Dock scale. This glow treatment belongs to the Dock artwork; the sidebar mascot and source vector remain flat. The native icon renderer and bundled `AppIcon.icns` use the same artwork.

[Dock icon PNG](../design-assets/dockey-dock-icon.png)

## Regenerate Dock assets

The native renderer in [`DockeyIcon.swift`](../Sources/Dockey/Design/DockeyIcon.swift) defines the Dock treatment. After changing it, run:

```sh
./scripts/generate-app-icon.sh
./scripts/build-app.sh
```

The generator builds the release renderer, exports `design-assets/dockey-dock-icon.png`, and uses Apple's `sips` and `iconutil` to create every canonical size in `Sources/Dockey/Resources/AppIcon.icns`. The normal app build afterward copies the updated ICNS into the SwiftPM resource bundle and final app. The generator's optional `--skip-build` is for an already-current renderer; regenerate and rebuild the bundle before distributing it.

## Action colors

Start uses muted green; Stop uses muted red. Text buttons use quiet tinted backgrounds, icon-only buttons gain a tinted hover surface, and Restart remains neutral. The colors are checked separately in light and dark themes.
