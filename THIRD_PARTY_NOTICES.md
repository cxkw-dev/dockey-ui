# Third-party notices

## Geist and Geist Mono

Dockey bundles unmodified Geist Sans and Geist Mono font files, distributed under the **SIL Open Font License, Version 1.1**. Copyright and license notices are retained beside the files:

- `Sources/Dockey/Resources/Fonts/Geist-OFL.txt`
- `Sources/Dockey/Resources/Fonts/GeistMono-OFL.txt`
- `prototypes/assets/fonts/Geist-OFL.txt`
- `prototypes/assets/fonts/GeistMono-OFL.txt`

The native app uses Geist Sans for its interface and window title and Geist Mono for logs and technical values. Source: [Vercel Geist](https://vercel.com/font).

## Rounded wordmark

The Dockey wordmark is project artwork vectorized from **Rounded 01**, the selected logo concept. The cropped reference is `design-assets/wordmark/rounded-reference.png`; its editable outline is `design-assets/wordmark/rounded-outline.svg`. Provenance, hashes, and tracing details are recorded in `design-assets/wordmark/SOURCE.json`. This artwork uses the repository's [Apache-2.0 license](LICENSE).

The wordmark uses compiled, cached native vector paths. It does not load its reference image or a wordmark font at runtime. Pillow and vtracer are development-only tracing tools, not bundled app dependencies. The app continues to bundle Geist and Geist Mono with the font notices above.

## Platform and external tools

SwiftUI, AppKit, Foundation, and system symbols are provided by macOS. Docker and Colima are external user-installed tools; their binaries are not redistributed by this repository or the Dockey app archive. Their own licenses and terms apply to those installations.

## Dockey artwork

The flat Dockey mascot and original repository illustrations are project assets under the repository's [Apache-2.0 license](LICENSE), including the Redis cache glyph and generic cube. The Lucide elephant and vendor marks under `design-assets/services/library/` and `design-assets/services/vendor/` are third-party material, not Dockey-owned artwork. See [service mark provenance](docs/service-icons.md).

The AI Focus F glyph comes from the project owner's existing application artwork and is distributed here under the repository's Apache-2.0 license. Its monochrome extraction and vectorization are recorded in `design-assets/services/AI_FOCUS_SOURCE.json`. No private app source or source-image metadata is included.

## Lucide Lab elephant

The PostgreSQL illustration uses Lucide Lab's generic full-body elephant, not the PostgreSQL/Slonik logo. Source: `lucide-icons/lucide-lab`, commit `34b6526d0a67bbe67b8a54b9b101018b1377ef28`, `icons/elephant.svg`. The upstream ISC notice includes copyrights for Lucide Contributors 2022 and Cole Bemis 2013–2022 for Feather-derived portions. Complete notice: `Sources/Dockey/Resources/ServiceIconLicenses/Lucide-Lab-ISC.txt`, also retained with source SVG, contributor metadata, and hashes under `design-assets/services/library/`.

Path geometry is unchanged; stroke width changes from 2 to 1.5 and theme gray is selected for the compact glyph. Derived SVG/PDF provenance records these changes. The ISC license permits modification and redistribution with its copyright/permission notice; Dockey retains that notice in source and app resources.

## Vendor service marks

Official geometry identifies software suggested by known image repositories. Pinned sources, hashes, supported monochrome variants, and serialization changes are recorded in `design-assets/services/vendor/SOURCES.json`. Offline-generated vector PDF renderings preserve those SVG geometries/colors for cached native rendering; conversion tools and hashes are recorded in `design-assets/services/PDF_SOURCES.json`.

- **ClickHouse:** Copyright 2016–2026 ClickHouse, Inc. Source: `ClickHouse/ClickHouse`, commit `7a1780997fcef514c87637e5564a94abc019d20f`, `docker/server/README.src/logo.svg`. Apache-2.0. Exact five mark paths retained; source clip bounds become the viewport, plate/CSS omitted, published monochrome foregrounds selected. Full notice: `Sources/Dockey/Resources/ServiceIconLicenses/ClickHouse-Apache-2.0.txt`.
- **Langfuse:** Copyright (c) 2022–2025 Langfuse GmbH. Source: `langfuse/langfuse-docs`, commit `327b0842b33c23cf080c66417e8bce363316302c`, `public/brand-assets/icon/monochrome/`. MIT. Supplied monochrome SVG geometry, viewport, and colors unchanged; XML serialization only. Full notice: `Sources/Dockey/Resources/ServiceIconLicenses/Langfuse-MIT.txt`.
- **Temporal:** Copyright (c) 2022 Temporal Technologies Inc. All rights reserved. Source: `temporalio/ui`, commit `c75f7143cb902871da2e6e14a125deb3179da9d7`, `src/lib/vendor/logo.svg` and `logo-dark.svg`. MIT. Path, viewport, and monochrome colors unchanged; unused XML metadata/fixed pixel dimensions removed. Full notice: `Sources/Dockey/Resources/ServiceIconLicenses/Temporal-MIT.txt`.
- **MongoDB:** Copyright 2022 MongoDB Inc. Source: `mongodb/leafygreen-ui`, commit `be0774c73ce70d359d112f3be7790c9ed0dce4a6`, `packages/logo/src/Logos/MongoDBLogoMark.tsx`. Apache-2.0. Exact standalone path/viewBox serialized without React props, using supported Black and White palette values. Full notice: `Sources/Dockey/Resources/ServiceIconLicenses/MongoDB-LeafyGreen-Apache-2.0.txt`.

The complete upstream licenses accompany the source assets in `design-assets/services/vendor/licenses/` and the app's resource bundle under `Resources/ServiceIconLicenses/`. No Docker, Vercel, Redis, or PostgreSQL logo is bundled. Vendor marks do not indicate sponsorship or certification.

## Product names

Product names identify software suggested by an image repository; they do not indicate image-provenance verification. ClickHouse, its logo, and related marks are trademarks or registered trademarks of ClickHouse, Inc. or its affiliates. Langfuse marks remain the property of their respective owners. MongoDB marks belong to MongoDB, Inc. Temporal marks belong to Temporal Technologies Inc. Redis is a registered trademark of Redis Ltd. Postgres, PostgreSQL, and Slonik marks belong to the PostgreSQL Community Association of Canada. All product names and marks remain the property of their respective owners. Dockey is independently developed and is not affiliated with or endorsed by these organizations, Docker, Colima, or Vercel.
