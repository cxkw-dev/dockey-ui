import Combine
import DockeyCore
import Foundation
import Testing

@testable import Dockey

@Suite("Event-driven application state")
@MainActor
struct AppStorePerformanceTests {
    @Test
    func inventoryIsUsableWithoutWaitingForMetricsStream() async throws {
        let fixture = try makeStore()
        defer {
            fixture.store.shutdown()
            fixture.cleanDefaults()
        }
        await fixture.store.start()
        try await settleInitialSubscription(fixture)
        #expect(fixture.store.isConnected)
        #expect(fixture.store.containers.count == 1)
        #expect(!fixture.store.isRefreshing)
        #expect(await fixture.runner.counts().statsStreams == 0)
        fixture.store.setApplicationActive(true)
        fixture.store.setMetricsVisible(true)
        try await waitUntil { await fixture.runner.counts().statsStreams == 1 }
        await fixture.runner.emitMetric(cpu: 25)
        try await waitUntil { fixture.store.stats[EventFixtureRunner.idA]?.cpuPercent == 25 }
        #expect(
            await fixture.runner.counts().oneShotStats == 0, "Live metrics must never use repeated --no-stream reads.")
        #expect(!fixture.store.isRefreshing)
    }

    @Test
    func idleEngineAndExecNoiseDoNotReadInventoryAndLifecycleBurstsCoalesce() async throws {
        let fixture = try makeStore()
        defer {
            fixture.store.shutdown()
            fixture.cleanDefaults()
        }
        await fixture.store.start()
        try await settleInitialSubscription(fixture)
        let before = await fixture.runner.counts()
        for action in ["exec_create", "exec_start", "exec_die", "attach", "detach"] {
            await fixture.runner.emitEvent(type: "container", action: action)
        }
        try await Task.sleep(for: .milliseconds(400))
        #expect(await fixture.runner.counts().inventory == before.inventory)
        await fixture.runner.setContainerState("exited")
        for action in ["stop", "die", "health_status: unhealthy", "stop"] {
            await fixture.runner.emitEvent(type: "container", action: action)
        }
        try await waitUntil { fixture.store.containers.first?.state == .exited }
        try await Task.sleep(for: .milliseconds(350))
        let after = await fixture.runner.counts()
        #expect(after.inventory == before.inventory + 1)
        #expect(after.contexts == before.contexts)
        #expect(after.info == before.info)
        #expect(!fixture.store.isRefreshing)
    }

    @Test
    func duplicateReconciliationsCoalesceAndPreserveVisibleRows() async throws {
        let fixture = try makeStore()
        defer {
            fixture.store.shutdown()
            fixture.cleanDefaults()
        }
        await fixture.store.start()
        try await settleInitialSubscription(fixture)
        let originalRows = fixture.store.containers
        let before = await fixture.runner.counts().inventory
        await fixture.runner.setInventoryDelay(.milliseconds(200))
        let first = Task { await fixture.store.refreshInBackground() }
        try await waitUntil { await fixture.runner.counts().inventory == before + 1 }
        #expect(!fixture.store.isRefreshing)
        #expect(fixture.store.isConnected)
        #expect(fixture.store.containers == originalRows)
        let second = Task { await fixture.store.refreshInBackground() }
        let third = Task { await fixture.store.refreshInBackground() }
        await first.value
        await second.value
        await third.value
        #expect(await fixture.runner.counts().inventory == before + 1)
        #expect(fixture.store.containers == originalRows)
    }

    @Test
    func manualRefreshForcesMetadataWithoutWaitingForPersistentMetrics() async throws {
        let fixture = try makeStore()
        defer {
            fixture.store.shutdown()
            fixture.cleanDefaults()
        }
        await fixture.store.start()
        try await settleInitialSubscription(fixture)
        try await waitUntil { fixture.store.engineInfo != nil }
        fixture.store.setApplicationActive(true)
        fixture.store.setMetricsVisible(true)
        try await waitUntil { await fixture.runner.counts().statsStreams == 1 }
        let before = await fixture.runner.counts()
        await fixture.runner.setInventoryDelay(.milliseconds(100))
        let refresh = Task { await fixture.store.refresh() }
        try await waitUntil { await fixture.runner.counts().inventory == before.inventory + 1 }
        #expect(fixture.store.isRefreshing)
        #expect(!fixture.store.containers.isEmpty)
        await refresh.value
        try await waitUntil { await fixture.runner.counts().info == before.info + 1 }
        #expect(await fixture.runner.counts().contexts == before.contexts + 1)
        #expect(await fixture.runner.counts().statsStreams == 1)
        #expect(await fixture.runner.counts().oneShotStats == 0)
        #expect(!fixture.store.isRefreshing)
    }

    @Test
    func resourceEventsInvalidateOnlyAffectedCachesAndNavigationReusesRows() async throws {
        let fixture = try makeStore()
        defer {
            fixture.store.shutdown()
            fixture.cleanDefaults()
        }
        await fixture.store.start()
        try await settleInitialSubscription(fixture)
        fixture.store.selectSection(.images)
        try await waitUntil { fixture.store.images.count == 1 }
        let before = await fixture.runner.counts()
        fixture.store.selectSection(.containers)
        fixture.store.selectSection(.images)
        await Task.yield()
        await Task.yield()
        #expect(await fixture.runner.counts().images == before.images)
        await fixture.runner.emitEvent(type: "image", action: "pull")
        try await waitUntil { await fixture.runner.counts().images == before.images + 1 }
        #expect(await fixture.runner.counts().inventory == before.inventory)
        await fixture.runner.emitEvent(type: "volume", action: "create")
        try await Task.sleep(for: .milliseconds(350))
        #expect(await fixture.runner.counts().volumes == 0, "Hidden categories are invalidated without eager reads.")
        fixture.store.selectSection(.volumes)
        try await waitUntil { await fixture.runner.counts().volumes == 1 }
    }

    @Test
    func contextChangesCancelOldSubscriptionsAndRejectTheirData() async throws {
        let fixture = try makeStore()
        defer {
            fixture.store.shutdown()
            fixture.cleanDefaults()
        }
        fixture.store.setApplicationActive(true)
        fixture.store.setMetricsVisible(true)
        await fixture.store.start()
        try await settleInitialSubscription(fixture)
        try await waitUntil { await fixture.runner.counts().statsStreams == 1 }
        await fixture.runner.emitMetric(cpu: 20)
        try await waitUntil { fixture.store.stats[EventFixtureRunner.idA] != nil }
        fixture.store.selectedContext = "local-b"
        #expect(!fixture.store.isConnected)
        #expect(fixture.store.containers.isEmpty)
        #expect(fixture.store.stats.isEmpty)
        await fixture.store.refreshInBackground()
        try await waitUntil { await fixture.runner.hasStreams(context: "local-b") }
        await fixture.runner.emitMetric(cpu: 99, context: "local-a")
        await fixture.runner.emitMetric(cpu: 80, context: "local-b")
        try await waitUntil { fixture.store.stats[EventFixtureRunner.idB]?.cpuPercent == 80 }
        #expect(fixture.store.containers.map(\.id) == [EventFixtureRunner.idB])
        #expect(fixture.store.stats[EventFixtureRunner.idA] == nil)
        #expect(fixture.store.engineInfo?.cpus == 4)
        #expect(await fixture.runner.counts().contexts == 2)
    }

    @Test
    func metricsRequireForegroundAndVisibleContentAndPublishOneBatchedFrame() async throws {
        let fixture = try makeStore()
        defer {
            fixture.store.shutdown()
            fixture.cleanDefaults()
        }
        await fixture.store.start()
        try await settleInitialSubscription(fixture)
        fixture.store.setMetricsVisible(true)
        await Task.yield()
        #expect(await fixture.runner.counts().statsStreams == 0)
        fixture.store.setApplicationActive(true)
        try await waitUntil { await fixture.runner.counts().activeStats == 1 }
        var publications = 0
        let subscription = fixture.store.$stats.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        for cpu in 1...20 { await fixture.runner.emitMetric(cpu: cpu) }
        #expect(fixture.store.stats.isEmpty, "Per-container rows should wait for the bounded publication window.")
        try await waitUntil { fixture.store.stats[EventFixtureRunner.idA]?.cpuPercent == 20 }
        #expect(publications == 1)
        fixture.store.setApplicationActive(false)
        try await waitUntil { await fixture.runner.counts().activeStats == 0 }
        #expect(fixture.store.stats[EventFixtureRunner.idA]?.cpuPercent == 20)
        fixture.store.setApplicationActive(true)
        try await waitUntil { await fixture.runner.counts().statsStreams == 2 }
        fixture.store.setMetricsVisible(false)
        try await waitUntil { await fixture.runner.counts().activeStats == 0 }
    }

    @Test
    func eventReconnectResynchronizesOnceThenStaysIdle() async throws {
        let fixture = try makeStore()
        defer {
            fixture.store.shutdown()
            fixture.cleanDefaults()
        }
        await fixture.store.start()
        try await settleInitialSubscription(fixture)
        let before = await fixture.runner.counts()
        await fixture.runner.disconnectEvents()
        try await waitUntil { await fixture.runner.counts().eventStreams == 2 }
        try await waitUntil { await fixture.runner.counts().inventory == before.inventory + 1 }
        try await Task.sleep(for: .milliseconds(350))
        #expect(await fixture.runner.counts().inventory == before.inventory + 1)
        #expect(!fixture.store.isRefreshing)
    }

    @Test
    func eventReaderDrainsIgnoredBurstsWhileInitialInventoryIsHeld() async throws {
        let fixture = try makeStore()
        await fixture.runner.holdInventoryReads()
        let startup = Task { await fixture.store.start() }
        defer {
            startup.cancel()
            fixture.store.shutdown()
            fixture.cleanDefaults()
            Task { await fixture.runner.releaseInventoryReads() }
        }
        try await waitUntil {
            let counts = await fixture.runner.counts()
            return counts.eventStreams == 1 && counts.inventory == 1
        }
        // Pace the producer to let the decoder run. The inventory gate remains closed
        // for the complete burst, exceeding the typed stream's 256-record capacity.
        for _ in 0..<320 {
            await fixture.runner.emitEvent(type: "container", action: "exec_start")
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await fixture.runner.counts().activeEvents == 1, "A held snapshot must not block the event reader.")
        await fixture.runner.releaseInventoryReads()
        await startup.value
        try await settleInitialSubscription(fixture)
        #expect(fixture.store.liveUpdateError == nil)
        #expect(await fixture.runner.counts().eventStreams == 1)
        #expect(await fixture.runner.counts().inventory == 2, "Ignored exec events must not queue extra snapshots.")
    }

    @Test
    func eventReconnectInvalidatesFreshResourceCacheAndUpdatesVisibleRows() async throws {
        let fixture = try makeStore()
        defer {
            fixture.store.shutdown()
            fixture.cleanDefaults()
        }
        await fixture.store.start()
        try await settleInitialSubscription(fixture)
        fixture.store.selectSection(.images)
        try await waitUntil { fixture.store.images.first?.repository == "fixture" && !fixture.store.isLoadingResources }
        let before = await fixture.runner.counts()
        await fixture.runner.disconnectEvents()
        await fixture.runner.setImageRepository("fixture-after-gap")
        try await waitUntil { await fixture.runner.counts().eventStreams == before.eventStreams + 1 }
        try await waitUntil {
            fixture.store.images.first?.repository == "fixture-after-gap" && !fixture.store.isLoadingResources
        }
        #expect(await fixture.runner.counts().images == before.images + 1)
        #expect(await fixture.runner.counts().inventory == before.inventory + 1)
        #expect(!fixture.store.isRefreshing)
    }

    @Test
    func bootstrapReplayStartsBeforeSlowInitialDiscoveryAndInventory() async throws {
        let fixture = try makeStore()
        defer {
            fixture.store.shutdown()
            fixture.cleanDefaults()
        }
        await fixture.runner.setDiscoveryDelay(.milliseconds(1_100))
        await fixture.store.start()
        try await settleInitialSubscription(fixture)
        let counts = await fixture.runner.counts()
        let replayStart = try #require(counts.firstReplaySince)
        let firstInventory = try #require(counts.firstInventoryAt)
        #expect(
            replayStart < Int(firstInventory.timeIntervalSince1970.rounded(.down)),
            "The replay timestamp must precede slow discovery, covering snapshot startup gaps.")
    }

    @Test
    func removedLastLocalContextInvalidatesCacheAndReportsFirstRefreshError() async throws {
        let fixture = try makeStore()
        defer {
            fixture.store.shutdown()
            fixture.cleanDefaults()
        }
        await fixture.store.start()
        try await settleInitialSubscription(fixture)
        await fixture.runner.removeLocalContexts()
        await fixture.store.refresh()
        #expect(fixture.store.selectedContext.isEmpty)
        #expect(!fixture.store.isConnected)
        #expect(fixture.store.containers.isEmpty)
        #expect(fixture.store.stats.isEmpty)
        #expect(fixture.store.connectionError?.contains("No local Docker context") == true)
        #expect(!fixture.store.isRefreshing)
    }

    private func makeStore() throws -> EventStoreFixture {
        let domain = "dev.dockey.event-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let runner = EventFixtureRunner()
        let client = DockerClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"), runner: runner)
        return EventStoreFixture(
            store: AppStore(defaults: defaults, client: client), runner: runner, defaults: defaults, domain: domain)
    }

    private func settleInitialSubscription(_ fixture: EventStoreFixture) async throws {
        try await waitUntil {
            let counts = await fixture.runner.counts()
            return counts.eventStreams == 1 && counts.inventory >= 2 && !fixture.store.isRefreshing
        }
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(4))
        while !(await condition()) {
            guard clock.now < deadline else { throw EventFixtureError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
private struct EventStoreFixture {
    let store: AppStore
    let runner: EventFixtureRunner
    let defaults: UserDefaults
    let domain: String
    func cleanDefaults() { defaults.removePersistentDomain(forName: domain) }
}

private enum EventFixtureError: Error { case timedOut }

private actor EventFixtureRunner: CommandRunning {
    static let idA = String(repeating: "a", count: 64)
    static let idB = String(repeating: "b", count: 64)
    struct Counts: Sendable {
        var contexts = 0
        var inventory = 0
        var info = 0
        var oneShotStats = 0
        var images = 0
        var volumes = 0
        var eventStreams = 0
        var statsStreams = 0
        var activeStats = 0
        var activeEvents = 0
        var firstReplaySince: Int?
        var firstInventoryAt: Date?
    }
    private struct Stream {
        let kind: String
        let context: String
        let continuation: AsyncThrowingStream<String, Error>.Continuation
    }
    private var value = Counts()
    private var streams: [UUID: Stream] = [:]
    private var terminated: Set<UUID> = []
    private var inventoryDelay = Duration.zero
    private var discoveryDelay = Duration.zero
    private var localContextsExist = true
    private var containerState = "running"
    private var imageRepository = "fixture"
    private var inventoryHeld = false
    private var inventoryWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    func counts() -> Counts { value }
    func setInventoryDelay(_ delay: Duration) { inventoryDelay = delay }
    func setDiscoveryDelay(_ delay: Duration) { discoveryDelay = delay }
    func removeLocalContexts() { localContextsExist = false }
    func setContainerState(_ state: String) { containerState = state }
    func setImageRepository(_ repository: String) { imageRepository = repository }
    func holdInventoryReads() { inventoryHeld = true }
    func releaseInventoryReads() {
        inventoryHeld = false
        let waiting = Array(inventoryWaiters.values)
        inventoryWaiters.removeAll()
        for continuation in waiting { continuation.resume() }
    }
    private func cancelInventoryRead(_ token: UUID) {
        inventoryWaiters.removeValue(forKey: token)?.resume(throwing: CancellationError())
    }
    private func waitForInventoryRelease() async throws {
        guard inventoryHeld else { return }
        let token = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if inventoryHeld {
                    inventoryWaiters[token] = continuation
                } else {
                    continuation.resume()
                }
            }
        } onCancel: {
            Task { await self.cancelInventoryRead(token) }
        }
    }
    func hasStreams(context: String) -> Bool {
        streams.values.contains { $0.context == context && $0.kind == "stats" }
            && streams.values.contains { $0.context == context && $0.kind == "events" }
    }
    func emitMetric(cpu: Int, context: String = "local-a") {
        let id = context == "local-b" ? Self.idB : Self.idA
        emit(
            "{\"ID\":\"\(id)\",\"CPUPerc\":\"\(cpu)%\",\"MemUsage\":\"1MiB / 1GiB\",\"MemPerc\":\"1%\",\"NetIO\":\"0B / 0B\",\"BlockIO\":\"0B / 0B\"}\n",
            kind: "stats", context: context)
    }
    func emitEvent(type: String, action: String, context: String = "local-a") {
        let id = context == "local-b" ? Self.idB : Self.idA
        emit(
            "{\"Type\":\"\(type)\",\"Action\":\"\(action)\",\"Actor\":{\"ID\":\"\(id)\"}}\n", kind: "events",
            context: context)
    }
    private func emit(_ text: String, kind: String, context: String) {
        for stream in streams.values where stream.kind == kind && stream.context == context {
            stream.continuation.yield(text)
        }
    }
    func disconnectEvents() {
        for stream in streams.values where stream.kind == "events" { stream.continuation.finish() }
    }

    func run(_ request: CommandRequest) async throws -> CommandOutput {
        let args = request.arguments
        let context = args.first == "--context" ? args.dropFirst().first : nil
        let id = context == "local-b" ? Self.idB : Self.idA
        if args.starts(with: ["context", "ls"]) {
            value.contexts += 1
            try await Task.sleep(for: discoveryDelay)
            guard localContextsExist else { return CommandOutput() }
            return CommandOutput(
                stdout: """
                    {"Name":"local-a","DockerEndpoint":"unix:///tmp/dockey-a.sock","Current":true}
                    {"Name":"local-b","DockerEndpoint":"unix:///tmp/dockey-b.sock","Current":false}
                    """)
        }
        if args.starts(with: ["context", "inspect"]) {
            return CommandOutput(stdout: "\"unix:///tmp/dockey-fixture.sock\"")
        }
        if args.contains("info") {
            value.info += 1
            let cpus = context == "local-b" ? 4 : 2
            return CommandOutput(
                stdout:
                    "{\"ServerVersion\":\"fixture\",\"Architecture\":\"arm64\",\"OperatingSystem\":\"test\",\"NCPU\":\(cpus),\"MemTotal\":1073741824}"
            )
        }
        if args.contains("container"), args.contains("ls") {
            value.inventory += 1
            if value.firstInventoryAt == nil { value.firstInventoryAt = Date() }
            try await waitForInventoryRelease()
            try await Task.sleep(for: inventoryDelay)
            return CommandOutput(stdout: id + "\n")
        }
        if args.contains("container"), args.contains("inspect") {
            return CommandOutput(
                stdout:
                    "[{\"Id\":\"\(id)\",\"Name\":\"/fixture-api\",\"Config\":{\"Image\":\"fixture:latest\",\"Labels\":{}},\"State\":{\"Status\":\"\(containerState)\"}}]"
            )
        }
        if args.contains("stats") { value.oneShotStats += 1 }
        if args.contains("image"), args.contains("ls") {
            value.images += 1
            return CommandOutput(
                stdout:
                    "{\"ID\":\"sha256:fixture\",\"Repository\":\"\(imageRepository)\",\"Tag\":\"latest\",\"Size\":\"1MB\",\"CreatedSince\":\"today\"}"
            )
        }
        if args.contains("volume"), args.contains("ls") { value.volumes += 1 }
        return CommandOutput()
    }

    nonisolated func stream(_ request: CommandRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let token = UUID()
            continuation.onTermination = { [weak self] _ in Task { await self?.removeStream(token) } }
            Task { await self.registerStream(request, token: token, continuation: continuation) }
        }
    }
    private func registerStream(
        _ request: CommandRequest, token: UUID, continuation: AsyncThrowingStream<String, Error>.Continuation
    ) {
        guard !terminated.contains(token) else {
            continuation.finish()
            return
        }
        let args = request.arguments
        let context = args.first == "--context" ? String(args[1]) : ""
        let kind = args.contains("events") ? "events" : "stats"
        streams[token] = Stream(kind: kind, context: context, continuation: continuation)
        if kind == "events" {
            value.eventStreams += 1
            value.activeEvents += 1
            if value.firstReplaySince == nil, let index = args.firstIndex(of: "--since"),
                args.indices.contains(index + 1)
            {
                value.firstReplaySince = Int(args[index + 1])
            }
        } else {
            value.statsStreams += 1
            value.activeStats += 1
        }
    }
    private func removeStream(_ token: UUID) {
        terminated.insert(token)
        switch streams.removeValue(forKey: token)?.kind {
        case "stats": value.activeStats -= 1
        case "events": value.activeEvents -= 1
        default: break
        }
    }
}
