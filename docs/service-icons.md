# Service illustrations and brand research

Dockey uses original service-identification illustrations: analytical columns, a leaf and document, cache layers, and a small elephant. Their glyphs are monochrome in both appearances. They belong to Dockey's quiet badge family and use the repository's [Apache-2.0 license](../LICENSE). They are **not official vendor logos**, copied logo paths, or evidence of vendor approval. Product names identify the software suggested by an image reference.

The original SVG artwork lives in `design-assets/services/`. No official vendor SVG or vendor-specific artwork license is bundled. Dockey does not fetch icons from the network at runtime. Keep the illustrations separate from the Dockey mascot and retain accessible product labels; the illustration alone should not determine identity.

## Why use original illustrations?

Official resources were reviewed on **October 28, 2026**. The policies distinguish copyright licensing, trademark use, and alterations. A public SVG download does not itself grant permission to recolor or redistribute a logo. The following is an implementation record, not a legal assurance; consult the current linked policies before introducing official marks.

| Product | Official evidence | Implication for an official logo |
| --- | --- | --- |
| ClickHouse® | [Trademark policy, version 2.0](https://clickhouse.com/legal/trademark-policy); [logo usage and downloads](https://clickhouse.design/brand/logo-usage) | The legal policy permits textual compatibility descriptions but directs logo-use requests to ClickHouse. Its design page describes broader identification uses. Both restrict alteration; the legal policy allows scaling and a limited black-and-white exception. This difference is unresolved for a redistributed app badge. Use the original Dockey columns illustration. |
| MongoDB® | [Trademark standards](https://www.mongodb.com/legal/trademark-usage-guidelines); [brand resources](https://www.mongodb.com/company/newsroom/brand-resources); [website terms](https://www.mongodb.com/legal/terms-of-use) | Product-identification use is described, but editing, recoloring, distorting, or reconfiguring the leaf is prohibited. The brand kit provides specific color variants; do not invent a Dockey-colored leaf logo. General website content also has redistribution restrictions. Use the original leaf-and-document illustration. |
| Redis® | [Trademark policy, updated September 15, 2026](https://redis.io/legal/trademark-policy/); [legal hub](https://redis.io/legal/); [documentation license](https://github.com/redis/docs/blob/main/LICENSE) | Truthful product identification is permitted subject to the policy and attribution. Redis prohibits imitating its visual identity. Current documentation assets are generally CC BY-NC-SA 4.0, with a legacy-content exception that needs asset-specific evidence. The legal hub's brand-portal link was unavailable during review. Use the original cache-layer illustration. |
| PostgreSQL® | [Trademark policy](https://www.postgresql.org/about/policies/trademarks/); [official logo catalog](https://wiki.postgresql.org/wiki/Logo); [SVG file record](https://wiki.postgresql.org/wiki/File:PostgreSQL_logo.3colors.svg) | The policy permits factual word references, restricts modifications and combined-logo presentations, and asks for approval for uses outside its listed cases. The SVG file record leaves its copyright license unspecified. Do not assume the database's software license licenses the elephant artwork. Use the original small-elephant illustration. |

Our illustrations must remain independent drawings. Do not trace official silhouettes, copy their vector coordinates, or turn them into near-identical recolored marks. If an illustration becomes confusingly similar to a vendor mark, replace it with a neutral database/document glyph and the product label.

## Official asset references, not bundled artwork

These are exact primary-source references found during research. They are retained as links for future review, not as approval to ship the files.

| Product | Official vector reference | Copyright/license evidence |
| --- | --- | --- |
| ClickHouse | [Black logomark SVG](https://clickhouse.design/images/brand/logos/logomark-black.svg), [white logomark SVG](https://clickhouse.design/images/brand/logos/logomark-white.svg) | Official downloads governed by the linked brand rules and trademark policy; no separate permissive artwork grant established. |
| MongoDB | [Full wordmark SVG, pinned official LeafyGreen source](https://raw.githubusercontent.com/mongodb/leafygreen-ui/be0774c73ce70d359d112f3be7790c9ed0dce4a6/tools/storybook-addon/static/logo.svg); [standalone leaf component source](https://github.com/mongodb/leafygreen-ui/blob/be0774c73ce70d359d112f3be7790c9ed0dce4a6/packages/logo/src/Logos/MongoDBLogoMark.tsx) | [LeafyGreen Apache-2.0 license](https://github.com/mongodb/leafygreen-ui/blob/be0774c73ce70d359d112f3be7790c9ed0dce4a6/LICENSE), Copyright 2022 MongoDB Inc. This copyright license does not remove the trademark restrictions above. Neither asset is used by Dockey. |
| Redis | [Redis cube SVG, pinned official documentation source](https://raw.githubusercontent.com/redis/docs/65aa9d2f0fc042368f43947fdd143104f1860409/assets/icons/redis-cube.svg) | [Pinned documentation license](https://github.com/redis/docs/blob/65aa9d2f0fc042368f43947fdd143104f1860409/LICENSE) generally specifies CC BY-NC-SA 4.0. No permissive asset-specific exception established for this SVG. |
| PostgreSQL | [Three-color SVG](https://wiki.postgresql.org/images/a/a4/PostgreSQL_logo.3colors.svg), [blue SVG](https://wiki.postgresql.org/images/9/90/PostgreSQL_logo.1color_blue.svg), [white SVG](https://wiki.postgresql.org/images/7/72/PostgreSQL_logo.1color_white.svg) | Official catalog subjects the logo to its trademark policy. The three-color file record does not identify a copyright license. |

Requests for uses outside published permissions can be directed to the contacts on the official policy pages. No permission request has been sent and no vendor approval has been obtained.

## How Dockey chooses an illustration

`ServiceIdentity` matches a small, explicit image-repository allowlist. It does not infer a product from a container name, Compose project, service name, substring, or arbitrary mirror. Tags and valid digests are normalized before repository matching.

| Illustration | Recognized Docker Hub repositories |
| --- | --- |
| Analytical columns | `clickhouse`, `clickhouse/clickhouse-server` |
| Leaf and document | `mongo`, `mongodb/mongodb-community-server`, `mongodb/mongodb-enterprise-server`, `mongodb/mongodb-atlas-local` |
| Cache layers | `redis`, `redis/redis-stack`, `redis/redis-stack-server` |
| Small elephant | `postgres` |

Docker Hub's explicit `library/` prefix and its known Official Images architecture namespaces are recognized for the single-name official repositories. Explicit `docker.io`, `index.docker.io`, and `registry-1.docker.io` hosts are accepted. Other registries, unrecognized namespaces, malformed references, and custom images retain the generic container illustration.

This is a **presentation hint**, not image verification. Matching a repository string does not verify signatures, content, software versions, supply-chain provenance, or permission to run an image.

Primary references for the repository allowlist:

- [Docker Official Images conventions and architecture namespaces](https://github.com/docker-library/official-images/blob/master/README.md).
- [ClickHouse Docker Official Image](https://hub.docker.com/_/clickhouse) and [ClickHouse Docker installation documentation](https://clickhouse.com/docs/install/docker).
- [MongoDB Community Server image](https://hub.docker.com/r/mongodb/mongodb-community-server/), [MongoDB Enterprise Docker documentation](https://www.mongodb.com/docs/manual/tutorial/install-mongodb-enterprise-with-docker/), and [Atlas local Docker documentation](https://www.mongodb.com/docs/atlas/cli/current/atlas-cli-deploy-docker/).
- [Redis Stack Docker documentation](https://redis.io/docs/latest/operate/oss_and_stack/install/archive/install-stack/docker/).

ClickHouse is a registered trademark of ClickHouse, Inc. MongoDB is a trademark or registered trademark of MongoDB, Inc. Redis is a registered trademark of Redis Ltd. Postgres, PostgreSQL, and the Slonik Logo are trademarks or registered trademarks of the PostgreSQL Community Association of Canada. Dockey is independently developed and is not endorsed, supported, or certified by these organizations.
