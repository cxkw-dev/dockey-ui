# Service identities, vendor marks, and provenance

Dockey uses recognizable official mark geometry for **ClickHouse, Langfuse, Temporal, and MongoDB**, in supplied or supported monochrome variants without an enclosing tile or border. PostgreSQL uses a full-body Lucide Lab elephant, not the PostgreSQL logo. Redis cache layers and the generic cube remain original Dockey illustrations. Product labels remain visible. An icon does not establish image authenticity, certification, or vendor approval.

The sanitized SVG sources live in [`design/services/vendor/`](../../design/services/vendor/). [`SOURCES.json`](../../design/services/vendor/SOURCES.json) records exact commits, raw SVG/component URLs, source/output SHA-256 values, complete licenses, and serialization changes. Full upstream licenses accompany the sources and the app under `Sources/Dockey/Resources/ServiceIconLicenses/`.

The app renders cached native vector PDFs generated offline from these SVGs. It does not need a runtime SVG engine, fetch icons, or contact a brand service. The generator, pinned conversion dependency, tool versions, and SVG/PDF hashes are recorded in [`PDF_SOURCES.json`](../../design/services/PDF_SOURCES.json) and the adjacent generator script. PDF conversion changes format, not the intended geometry, proportions, or foreground colors.

## Official source and license record

Reviewed October 28, 2026. Copyright licenses and trademark policies serve different purposes. This records the basis for narrow service identification, not a legal guarantee or a claim of separate vendor approval.

| Mark | Pinned official source | Copyright license and normalization |
| --- | --- | --- |
| ClickHouse | [Core Docker artwork](https://github.com/ClickHouse/ClickHouse/blob/7a1780997fcef514c87637e5564a94abc019d20f/docker/server/README.src/logo.svg) | [Apache-2.0](https://github.com/ClickHouse/ClickHouse/blob/7a1780997fcef514c87637e5564a94abc019d20f/LICENSE), Copyright 2016–2026 ClickHouse, Inc. The five mark paths retain exact coordinates. Existing clip bounds become the viewport; background/CSS are omitted and published monochrome foregrounds selected. The separately licensed `docs/` tree is not the source. |
| Langfuse | [Official monochrome icon](https://github.com/langfuse/langfuse-docs/blob/327b0842b33c23cf080c66417e8bce363316302c/public/brand-assets/icon/monochrome/langfuse-icon-monochrome.svg) and [white variant](https://github.com/langfuse/langfuse-docs/blob/327b0842b33c23cf080c66417e8bce363316302c/public/brand-assets/icon/monochrome/langfuse-icon-monochrome-white.svg) | [MIT](https://github.com/langfuse/langfuse-docs/blob/327b0842b33c23cf080c66417e8bce363316302c/LICENSE), Copyright 2022–2025 Langfuse GmbH. XML serialization only; geometry, viewBox, fill rules, and supplied colors unchanged. |
| Temporal | [Official white mark](https://github.com/temporalio/ui/blob/c75f7143cb902871da2e6e14a125deb3179da9d7/src/lib/vendor/logo.svg) and [dark mark](https://github.com/temporalio/ui/blob/c75f7143cb902871da2e6e14a125deb3179da9d7/src/lib/vendor/logo-dark.svg) | [MIT](https://github.com/temporalio/ui/blob/c75f7143cb902871da2e6e14a125deb3179da9d7/LICENSE), Copyright 2022 Temporal Technologies Inc. Path, viewport, and supplied monochrome colors unchanged; unused XML metadata and fixed pixel dimensions removed. |
| MongoDB | [Standalone LogoMark component](https://github.com/mongodb/leafygreen-ui/blob/be0774c73ce70d359d112f3be7790c9ed0dce4a6/packages/logo/src/Logos/MongoDBLogoMark.tsx) | [Apache-2.0](https://github.com/mongodb/leafygreen-ui/blob/be0774c73ce70d359d112f3be7790c9ed0dce4a6/LICENSE), Copyright 2022 MongoDB Inc. Exact SVG path/viewBox serialized without React props. The component's [supported options](https://github.com/mongodb/leafygreen-ui/blob/be0774c73ce70d359d112f3be7790c9ed0dce4a6/packages/logo/src/Logo.types.ts) and [palette](https://github.com/mongodb/leafygreen-ui/blob/be0774c73ce70d359d112f3be7790c9ed0dce4a6/packages/palette/src/palette.ts) supply Black (`#001E2B`) and White (`#FFFFFF`). |

SVGs contain only static vector elements, without JavaScript, event handlers, external assets, or remote references. Preserve complete copyright/license notices in source and app archives. Dockey's Apache-2.0 license does not transfer ownership of vendor marks or relicense MIT material.

The PostgreSQL illustration comes from [Lucide Lab's elephant SVG](https://github.com/lucide-icons/lucide-lab/blob/34b6526d0a67bbe67b8a54b9b101018b1377ef28/icons/elephant.svg), under its [ISC license](https://github.com/lucide-icons/lucide-lab/blob/34b6526d0a67bbe67b8a54b9b101018b1377ef28/LICENSE). The exact upstream SVG, contributor metadata, and source hashes are retained in [`design/services/library/`](../../design/services/library/). Dockey preserves path geometry, uses theme gray, and adjusts stroke width from 2 to 1.5 for the compact glyph. Derived SVG/PDF references document these changes. The complete ISC notice is bundled as `Resources/ServiceIconLicenses/Lucide-Lab-ISC.txt`; this glyph is not original Dockey artwork or a claim to Slonik ownership.

## Brand-use scope

- **ClickHouse:** its [design guide](https://clickhouse.design/brand/logo-usage) permits truthful descriptions of ClickHouse products and supplies black/white logomarks. Its [trademark policy](https://clickhouse.com/legal/trademark-policy) restricts logo use in compatibility statements and limits alterations, with a black-and-white exception. Apache-2.0 section 6 preserves customary origin-identification uses; it is not a blanket trademark license. Dockey uses the mark to identify ClickHouse software suggested by a known repository, without claiming API compatibility or certification. This is the implementation's narrow origin-identification rationale, not separate written vendor approval.
- **Langfuse:** the [official brand page](https://langfuse.com/brand) explicitly provides these monochrome assets for integrations and asks that they remain unmodified and not imply sponsorship. Dockey preserves the supplied shapes and colors.
- **Temporal:** its [official brand page](https://temporal.io/brand) supplies monochrome logomarks. Dockey retains the standalone MIT UI mark's geometry/colors and does not present it as Dockey branding or Temporal certification.
- **MongoDB:** its [trademark standards](https://www.mongodb.com/legal/trademark-usage-guidelines) allow product identification and prohibit editing, distorting, or arbitrary recoloring of the leaf. Dockey uses the official standalone component with its own Black/White options, rather than a newly drawn leaf or an invented accent.

Redis retains an original Dockey illustration. Review its [trademark policy](https://redis.io/legal/trademark-policy/) and [documentation license](https://github.com/redis/docs/blob/main/LICENSE) before adding vendor artwork. PostgreSQL's [trademark policy](https://www.postgresql.org/about/policies/trademarks/) covers Slonik, and its [SVG file record](https://wiki.postgresql.org/wiki/File:PostgreSQL_logo.3colors.svg) does not specify a copyright license. The independently licensed Lucide animal glyph is used instead of that vendor logo.

Do not arbitrarily tint vendor marks, simplify their paths, combine them with the mascot, add decorative effects, or label them as Dockey-owned. Select the supplied variant for the current app appearance. No vendor endorsement or certification has been obtained or claimed.

## Image recognition

AI Focus uses the project owner's current F mark, extracted from its existing app icon as a standalone monochrome silhouette. The yellow tile is omitted. Its derivation and hashes are recorded in [`AI_FOCUS_SOURCE.json`](../../design/services/AI_FOCUS_SOURCE.json). This custom identification is limited to the explicitly configured, unqualified `ai-focus` repository; it does not assign that identity to arbitrary namespaces or registries.

Every row reserves the same 24-point icon slot. Actual drawing sizes balance visible weight: ClickHouse and AI Focus use 18 points, Langfuse/Temporal/PostgreSQL 22, and MongoDB 23 for its narrow leaf. AI Focus has a half-point optical shift to balance its heavier left stem. Source geometry and aspect ratios remain intact. Original Redis and generic glyphs retain their drawing grids.

`ServiceIdentity` matches explicit registry/repository pairs. Container names, Compose service names, substrings, and arbitrary mirrors do not establish a match. Tags and valid digests are normalized first.

| Service | Recognized repositories |
| --- | --- |
| ClickHouse | Docker Hub `clickhouse`, `clickhouse/clickhouse-server` |
| MongoDB | Docker Hub `mongo`, `mongodb/mongodb-community-server`, `mongodb/mongodb-enterprise-server`, `mongodb/mongodb-atlas-local` |
| Redis | Docker Hub `redis`, `redis/redis-stack`, `redis/redis-stack-server` |
| PostgreSQL | Docker Hub `postgres` |
| Langfuse | `langfuse/langfuse` and `langfuse/langfuse-worker` on Docker Hub, `ghcr.io`, or `docker.langfuse.com` |
| Temporal | Docker Hub `temporalio/auto-setup`, `temporalio/server`, `temporalio/temporal`, `temporalio/admin-tools`, `temporalio/ui` |
| AI Focus | Explicit local custom image `ai-focus`, with a valid optional tag or digest |

Docker Hub aliases (`docker.io`, `index.docker.io`, `registry-1.docker.io`), `library/`, and known Official Images architecture namespaces are handled explicitly. Other registries, custom namespaces, malformed references, and unrecognized repositories retain the generic cube. A familiar path on another registry is not treated as vendor-owned.

Matching is a **presentation hint**, not verification of signatures, image contents, versions, supply-chain provenance, or permission to run an image. Recognizing an existing deprecated image does not recommend installing it.

Primary image references:

- [Docker Official Images conventions](https://github.com/docker-library/official-images/blob/master/README.md), [ClickHouse's Official Image](https://hub.docker.com/_/clickhouse).
- [MongoDB Community Server](https://hub.docker.com/r/mongodb/mongodb-community-server/), [Enterprise Docker instructions](https://www.mongodb.com/docs/manual/tutorial/install-mongodb-enterprise-with-docker/), [Atlas local Docker instructions](https://www.mongodb.com/docs/atlas/cli/current/atlas-cli-deploy-docker/).
- [Redis Stack Docker instructions](https://redis.io/docs/latest/operate/oss_and_stack/install/archive/install-stack/docker/).
- [Langfuse registry and Docker Hub substitution](https://langfuse.com/self-hosting/security/telemetry), [official Compose](https://github.com/langfuse/langfuse/blob/main/docker-compose.yml), [GHCR web](https://github.com/langfuse/langfuse/pkgs/container/langfuse), [GHCR worker](https://github.com/langfuse/langfuse/pkgs/container/langfuse-worker).
- [Temporal official server/UI/Admin Tools Compose](https://github.com/temporalio/samples-server/blob/main/compose/docker-compose.yml), [CLI container instructions](https://docs.temporal.io/cli/setup-cli), [legacy auto-setup image](https://hub.docker.com/r/temporalio/auto-setup).

ClickHouse and related marks belong to ClickHouse, Inc. or its affiliates. Langfuse marks remain their respective owners' property. MongoDB marks belong to MongoDB, Inc. Temporal marks belong to Temporal Technologies Inc. Redis is a registered trademark of Redis Ltd. Postgres, PostgreSQL, and Slonik marks belong to the PostgreSQL Community Association of Canada. Dockey is independently developed and is not endorsed, supported, or certified by these organizations.
