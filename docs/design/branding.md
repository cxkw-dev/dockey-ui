# Dockey

Product name: **Dockey**. Selected layout: **A — Grouped list**.

## Wordmark

The wordmark follows **Rounded 01**, the selected concept-board lettering. Preserve its rounded letterforms and proportions when editing the outline. It uses a single foreground color: light on dark surfaces and charcoal on light surfaces. The teal-outlined mascot provides the color accent.

This is project artwork traced from the approved [cropped PNG reference](../../design/wordmark/rounded-reference.png). The [editable outline](../../design/wordmark/rounded-outline.svg), portable [SVG](../../design/dockey-wordmark.svg), and cached native Shape share the selected lettering. [SOURCE.json](../../design/wordmark/SOURCE.json) records provenance, hashes, and the offline conversion. No script or serif font is used for the wordmark.

Regenerate the outline and native exports offline on macOS:

```sh
uv run scripts/assets/trace-wordmark.py
swift scripts/assets/generate-wordmark.swift
./scripts/build-app.sh
```

Pillow and vtracer are pinned development-only tools in the tracing script's metadata. The Swift exporter checks the outline against `SOURCE.json`, writes portable SVG and a cached native Shape, and computes the filled-area optical center offline. Update the recorded outline hash after an intentional manual SVG edit. The app renders the compiled vectors without image/font loading, tracing, or optical-center sampling at runtime.

One shared component aligns the lettering's filled-area center with the mascot. Proportions are mascot 32 / lettering 26 / gap 3 points in the sidebar, and 70 / 56 / 6 in About. The version sits separately below About's brand component. Both themes were visually checked in native exports and the installed app; see the [verification record](../dev/verification.md). The README's theme-specific header PNGs use the same native component with transparency.

**Geist Sans** remains the interface typeface and the small window title uses weight 500 for legibility. Geist Mono remains the typeface for logs and technical values. The Geist families are bundled locally with their SIL Open Font Licenses. Source: [Vercel Geist](https://vercel.com/font).

## Mark

The mark is a flat, charcoal puff with large off-white eyes, two tiny feet, and a small teal shipping container. It follows the requested soot-sprite-inspired direction using simple filled shapes. There are no gradients, textures, highlights, shadows, or raster images in the final mark.

Source: `design/dockey-mark.svg`, which the browser prototypes also load. Preview the mark on light and dark surfaces and at small sizes in `design/prototypes/brand.html`.

Keep the mark small beside the name in the sidebar. A larger version can appear in About and the empty state. Resource icons and lifecycle controls retain the existing restrained SVG icon system.

The native app mascot adds the Dock artwork's pale teal outline to the sidebar, About, and empty states. The outline scales for readability at the small sidebar size; the character stays flat, with no glow or shadow inside the app. The source SVG retains the original flat mark.

The macOS Dock icon uses a matte charcoal tile and a larger mascot, with a brighter teal rim and halo that remain visible at Dock scale. The glow belongs to the Dock artwork. The native icon renderer and bundled `AppIcon.icns` use the same artwork.

[Dock icon PNG](../../design/dockey-dock-icon.png)

## Regenerate Dock assets

The native renderer in [`DockeyIcon.swift`](../../Sources/Dockey/Design/DockeyIcon.swift) defines the Dock treatment. After changing it, run:

```sh
./scripts/generate-app-icon.sh
./scripts/build-app.sh
```

The generator builds the release renderer, exports `design/dockey-dock-icon.png`, and uses Apple's `sips` and `iconutil` to create every canonical size in `Sources/Dockey/Resources/AppIcon.icns`. The normal app build afterward copies the updated ICNS into the SwiftPM resource bundle and final app. The generator's optional `--skip-build` is for an already-current renderer; regenerate and rebuild the bundle before distributing it.

## Action colors

Start uses muted green; Stop uses muted red. Text buttons use quiet tinted backgrounds, icon-only buttons gain a tinted hover surface, and Restart remains neutral. The colors are checked separately in light and dark themes.
