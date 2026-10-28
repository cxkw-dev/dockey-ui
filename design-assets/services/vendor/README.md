# Vendor service marks

These are official vendor mark geometries used for factual service identification,
not Dockey-owned illustrations. No vendor endorsement or certification is claimed.

[`SOURCES.json`](SOURCES.json) records exact source commits/URLs, source and output
SHA-256 values, complete licenses, and serialization changes. Full license texts
are in [`licenses/`](licenses/) and `Sources/Dockey/Resources/ServiceIconLicenses/`.

| Mark | Official source and license | Normalization |
| --- | --- | --- |
| ClickHouse | `ClickHouse/ClickHouse`, Apache-2.0 | Five exact paths selected from Docker artwork outside the separately licensed `docs/` tree. Existing clip bounds become the viewport; background/CSS omitted; published monochrome foregrounds selected. Path coordinates unchanged. |
| Langfuse | `langfuse/langfuse-docs`, MIT | Supplied monochrome and monochrome-white icons; XML serialization only. |
| Temporal | `temporalio/ui`, MIT | Official standalone mark; unused metadata and fixed pixel dimensions removed. Geometry, viewport, and original monochrome colors retained. |
| MongoDB | `mongodb/leafygreen-ui`, Apache-2.0 | Standalone LogoMark component serialized without React props. Exact path/viewBox retained; supported Black (`#001E2B`) and White (`#FFFFFF`) selected. |

Preserve aspect ratio, supplied colors, and separation from the Dockey mascot.
Do not arbitrarily tint, simplify paths, add decorative logo elements, or imply
image authenticity. Dockey draws no enclosing badge background or border.
Offline-generated PDF renderings are derived from these SVGs; their tool versions
and hashes are recorded separately in `../PDF_SOURCES.json`.
See [service identity and policy notes](../../../docs/service-icons.md).
