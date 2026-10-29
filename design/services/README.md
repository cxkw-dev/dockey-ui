# Service artwork

Four service families use reviewed upstream standalone marks: ClickHouse,
Langfuse, Temporal, and MongoDB. The sanitized, editable SVGs, pinned source
commits, licenses, hashes, and change notes live in
[`vendor/SOURCES.json`](vendor/SOURCES.json). Their path geometry and official
light/dark colors are preserved. Product marks remain their owners' property;
identification does not imply affiliation, approval, or image authenticity.

The app loads cached native vector PDFs, preserving aspect ratio with no plate
or border. [`generate-vendor-pdfs.py`](generate-vendor-pdfs.py) converts the local
reviewed SVGs offline with pinned CairoSVG. It fixes PDF metadata dates and
checks repeat conversion produces identical bytes. Tool versions and SVG/PDF
hashes are recorded in [`PDF_SOURCES.json`](PDF_SOURCES.json). Dockey has no
runtime Python, Cairo, network, or SVG-rendering dependency. The bundled copies
of the SVGs remain available for resource auditing.

AI Focus uses the project owner's existing F mark without its yellow tile. The
standalone monochrome SVGs and vectorization record are in
[`AI_FOCUS_SOURCE.json`](AI_FOCUS_SOURCE.json). Its image mapping is explicitly
limited to the local custom `ai-focus` repository.

PostgreSQL uses Lucide Lab's general-purpose full-body elephant illustration,
licensed under ISC. It is distinct from the PostgreSQL vendor mark. The pinned
source, contributors, license, and rendering changes are recorded in
[`library/SOURCES.json`](library/SOURCES.json). The original path geometry and
viewBox are preserved; theme colors and a 1.5-point stroke fit the compact UI.
It uses the same cached native PDF rendering as the company marks.

Redis (three front-facing cache lines) and the generic container cube are
original Dockey glyphs under the project's [Apache-2.0 license](../../LICENSE).
Their light/dark SVG references match the native drawing in
[`ServiceIcon.swift`](../../Sources/Dockey/Design/ServiceIcon.swift).

Repository matching lives in `DockeyCore.ServiceIdentity`. It uses known image
repositories rather than container names; unrecognized images use the generic
cube. See [service identification](../../docs/design/service-icons.md) for the matching
policy and its limits.
