# Service illustrations

These are original Dockey illustrations, distributed under the project's
[Apache-2.0 license](../../LICENSE). No vendor artwork, SVG paths, tracing, or
external icon library was used to create them. Product names identify the image
repository; the illustrations do not imply vendor affiliation, approval, or
image authenticity.

| Image family | Original concept |
| --- | --- |
| ClickHouse | Three rounded analytics columns |
| MongoDB | A folded document with a broad diagonal leaf |
| Redis | Three front-facing cache lines |
| PostgreSQL | A small front-facing elephant character |
| Generic | An outlined container cube |

Every illustration uses a 24 × 24 coordinate system, a neutral tile with a
6-point corner radius, and a muted accent. Light and dark references use the
same geometry. The production app draws the matching geometry directly in
[`ServiceIcon.swift`](../../Sources/Dockey/Design/ServiceIcon.swift), so it does
not need SVG parsing, asset downloads, or a new rendering dependency.

Repository matching lives in `DockeyCore.ServiceIdentity`. It uses known image
repositories rather than container names; unrecognized images use the generic
cube. See [service identification](../../docs/service-icons.md) for the matching
policy and its limits.
