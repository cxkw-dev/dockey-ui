# Live updates and responsiveness

Dockey keeps a scoped in-memory snapshot on screen, with Docker events driving container changes. Optional metrics arrive through a separate persistent stats stream while visible. Nothing in this cache is written to disk.

## Measured bottleneck

A read-only probe against the local Colima environment in the [verification record](verification.md) measured two passes:

| Docker CLI operation | Observed duration |
| --- | --- |
| Context list | 14–16 ms |
| Context inspection | 13–15 ms |
| Container ID listing | 60–61 ms |
| Inspect listed containers | 31–33 ms |
| Engine information | 78–83 ms |
| Stats, one sample | 1.83–1.88 s |

Metrics accounted for about 90% of this serial command probe. These are CLI timings for one environment, not a frame-rate or whole-app startup benchmark.

## Live-update contract

- A fast inventory pass publishes containers without waiting for stats or engine information.
- There is no repeating inventory polling loop. Relevant Docker events trigger a coalesced reconciliation; unrelated exec and attachment events do not reload the container list.
- A persistent stats stream runs while metrics are visible and the app is active. Updates are batched before publishing to SwiftUI. Previous metrics remain visible while a new stream starts; metrics for removed or inactive containers are discarded.
- Event-stream reconnects trigger one fresh snapshot to cover missed changes, with bounded retry backoff if the engine is unavailable. Manual refresh remains available.
- Initial subscription uses an inclusive replay timestamp captured before discovery and inventory reads, closing the startup subscription gap.
- Stable context and engine metadata are cached. Manual refresh forces metadata discovery; cache expiry is checked when a read is needed, without a metadata polling timer.
- Images, volumes, and networks load on demand, with a 15-second cache per resource category. Revisiting a tab does not start a full inventory refresh.
- Identical snapshots do not publish redundant SwiftUI updates. Duplicate requests coalesce.
- Context or executable changes immediately cancel pending reads and clear cached resources. Generation checks reject late responses from the previous scope.
- Lifecycle actions re-resolve targets from the current snapshot. Docker's local-endpoint validation remains uncached at the operation boundary.

The cache improves responsiveness without treating an old snapshot as permission to change a different engine. Logs remain bounded in memory; they are separate from the metadata cache.

## Verification and further profiling

The application-state tests use controlled responses to verify that slow metrics do not hold up inventory, event updates coalesce while preserving visible rows, manual refresh forces metadata, tab navigation uses its cache, and stale-context responses are rejected. Stream tests cover framing, local scope, stderr isolation, and child-process cancellation. Run `./scripts/check.sh` for these regressions.

Apple recommends measuring long or frequent SwiftUI updates, keeping non-UI work off the main thread, and caching repeated calculations where appropriate. See [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance) and [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).

With full Xcode installed, use the SwiftUI, Time Profiler, Hangs, and Hitches instruments to measure interactions with representative workloads. This local verification uses Command Line Tools, real CLI timing, concurrency regressions, and native app checks; it does not claim a full Instruments frame-time profile or universal performance results.
