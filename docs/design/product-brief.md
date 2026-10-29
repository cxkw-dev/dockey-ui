# Dockey product brief

Status: SwiftUI/AppKit accepted; A (Grouped list) selected as the product direction.

Start actions use muted green and Stop actions use muted red in both themes. Container rows retain icon-only controls; project actions use lightly tinted buttons.

## Audience and purpose

Mac developers who already run Docker Engine through an approved local runtime and want a compact native interface for daily container and Compose work. The first supported runtime is an existing Colima installation. The application is SwiftUI with AppKit where native tables, split views, menus, shortcuts, and window behavior benefit from it.

The primary job: find a project, understand which services are running, start or stop it, and inspect a failing service without losing the surrounding project context.

## Principles

1. Compose projects are the default hierarchy. Aggregate running, stopped, unhealthy, and transitional states accurately.
2. App-created groups are organizational metadata, scoped to an engine context. They do not create Compose projects or imply dependency ordering.
3. Start existing containers, apply a Compose configuration, stop a project, and remove resources are visibly different operations.
4. Keep existing engines and data in place. Quitting the app leaves the engine and containers running by default.
5. Prefer focused tables, clear hierarchy, small readable metadata, and keyboard access over decorative dashboards.
6. Separate application preferences, runtime settings, and per-container/project configuration.

## Prototype directions

| Direction | Structure | Best use | Cost |
| --- | --- | --- | --- |
| A: Grouped list | Sources sidebar; expandable projects in a full-width table; separate detail view | Familiar overview across several projects | Opening a detail view temporarily replaces the overview |
| B: Project workspace | Project navigation; project header; service table; project tabs | Working within one Compose project at a time | Less simultaneous visibility across projects |
| C: Inspector | Sources sidebar; compact hierarchy; persistent detail inspector | Frequently jumping between containers and logs | More horizontal space needed; inspector moves below the list at narrow widths |

Each direction uses the same sample data, visual tokens, operation semantics, and settings model.

## First native release

Engine connection/status, local context selection, Compose grouping, container list, search/filter, start/stop/restart, logs, inspection, basic resource metrics, port links, image/volume/network inspection, appearance preferences, and clear operation progress/errors.

Follow with imported Compose file management, image pulls and run-container creation, custom groups, resource deletion with exact previews, and richer runtime management. These later flows are explored in the prototype so the layout can accommodate them, but they are not all promised for the first release.

## Acceptance criteria before implementation expands

- Launch from Finder and find installed tools without relying on an interactive shell's PATH.
- Remember the selected connection within the app without switching the global CLI context.
- Recover from disconnected/stopped engines, sleep/wake, missing CLI/Compose, stale resources, and partial operation failures.
- Keep UI state synchronized through engine events plus reconciliation; bound log buffers.
- Verify light/dark contrast, keyboard focus, resizing, compact/comfortable density, and adjustable log size.
- Use disposable engine resources for mutation tests. Unit-test grouping/operation planning with synthetic fixtures.
- Validate a signed/notarized development build early; distribution is separate from App Store submission.
