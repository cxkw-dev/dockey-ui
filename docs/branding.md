# Dockey

Product name: **Dockey**. Selected layout: **A — Grouped list**.

## Wordmark

The wordmark uses bold, connected script lettering inspired by the supplied reference, flattened to a single foreground color. It is light on dark surfaces and charcoal on light surfaces. There is no surrounding badge, extrusion, texture, or shadow. The teal-outlined mascot remains the color accent.

The lettering is shaped from **Leckerli One**, with a slight additional forward lean, and exported to static native paths and a portable [SVG](../design-assets/dockey-wordmark.svg). Rounded brush strokes give it a softer, heavier silhouette. Pinned source, hashes, and licensing are recorded in [wordmark/SOURCE.json](../design-assets/wordmark/SOURCE.json). The upstream font and notices live under `design-assets/wordmark/vendor/`; the app bundles the notices but does not load or ship the script font at runtime.

Regenerate both vector representations offline on macOS using `swift scripts/generate-wordmark.swift`. The generator checks the source font's pinned SHA-256 before exporting. A shared brand component keeps the mascot and wordmark aligned: the sidebar lettering is 28 points high with a 3-point optical downward adjustment, and About scales this to 42 points. The version label sits below the About component so it cannot displace the lettering relative to the mascot. The native path is cached; rendering performs no font shaping, file reads, or image decoding.

**Geist Sans** remains the interface typeface and the small window title uses weight 500 for legibility. Geist Mono remains the typeface for logs and technical values. The Geist families are bundled locally with their SIL Open Font Licenses. Source: [Vercel Geist](https://vercel.com/font).

## Mark

The mark is a flat, charcoal puff with large off-white eyes, two tiny feet, and a small teal shipping container. It follows the requested soot-sprite-inspired direction using simple filled shapes. There are no gradients, textures, highlights, shadows, or raster images in the final mark.

Source: `design-assets/dockey-mark.svg`. The identical prototype export is `prototypes/assets/dockey-mark.svg`. Preview the mark on light and dark surfaces and at small sizes in `prototypes/brand.html`.

Keep the mark small beside the name in the sidebar. A larger version can appear in About and the empty state. Resource icons and lifecycle controls retain the existing restrained SVG icon system.

The native app mascot adds the Dock artwork's pale teal outline to the sidebar, About, and empty states. The outline scales for readability at the small sidebar size; the character stays flat, with no glow or shadow inside the app. The source SVG retains the original flat mark.

The macOS Dock icon uses a matte charcoal tile and a larger mascot, with a brighter teal rim and halo that remain visible at Dock scale. The glow belongs to the Dock artwork. The native icon renderer and bundled `AppIcon.icns` use the same artwork.

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
