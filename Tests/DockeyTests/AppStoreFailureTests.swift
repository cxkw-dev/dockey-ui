import DockeyCore
import Foundation
import Testing

@testable import Dockey

@Suite("Visible failures and retries")
@MainActor
struct AppStoreFailureTests {
    @Test
    func inspectionFailureAndRetryDoNotPretendTheContainerHasNoMounts() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        await fixture.store.start()
        try await waitUntil { await fixture.runner.inventoryReads >= 2 && !fixture.store.isRefreshing }
        let container = try #require(fixture.store.containers.first)
        fixture.store.selectedContainerID = container.id
        await fixture.runner.failInspection(true)
        await fixture.store.refreshDetail()
        #expect(fixture.store.inspection == nil)
        #expect(fixture.store.inspectionError != nil)
        #expect(!fixture.store.isLoadingInspection)
        try await waitUntil { fixture.store.logStreamState == .following }
        #expect(fixture.store.logError == nil, "Inspection failure must not prevent the independent log connection.")

        await fixture.runner.failInspection(false)
        await fixture.store.retryInspection()
        #expect(fixture.store.inspectionError == nil)
        #expect(fixture.store.inspection?.mounts.isEmpty == false)
        let previous = fixture.store.inspection?.json
        await fixture.runner.failInspection(true)
        await fixture.store.retryInspection()
        #expect(fixture.store.inspection?.json == previous, "Keep the last good inspection with an explicit stale error.")
        #expect(fixture.store.inspectionError != nil)
    }

    @Test
    func resourceErrorsAreScopedToTheirCategoryAndRetryKeepsLastGoodRows() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        await fixture.store.start()
        try await waitUntil { await fixture.runner.inventoryReads >= 2 && !fixture.store.isRefreshing }
        await fixture.runner.failImages(true)
        fixture.store.selectSection(.images)
        try await waitUntil { !fixture.store.isLoadingResources && fixture.store.resourceError != nil }
        #expect(fixture.store.images.isEmpty)

        fixture.store.selectSection(.volumes)
        try await waitUntil { fixture.store.volumes.count == 1 && !fixture.store.isLoadingResources }
        #expect(fixture.store.resourceError == nil)
        fixture.store.selectSection(.images)
        #expect(fixture.store.resourceError != nil, "A failed category must not become a healthy empty state after navigation.")
        await fixture.runner.failImages(false)
        await fixture.store.retryResources()
        #expect(fixture.store.resourceError == nil)
        #expect(fixture.store.images.count == 1)
        let previous = fixture.store.images
        await fixture.runner.failImages(true)
        await fixture.store.retryResources()
        #expect(fixture.store.images == previous)
        #expect(fixture.store.resourceError != nil)
    }

    @Test
    func lateResourceFailureCannotLeakIntoAnotherContext() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        await fixture.store.start()
        try await waitUntil { await fixture.runner.inventoryReads >= 2 && !fixture.store.isRefreshing }
        await fixture.runner.holdImages()
        fixture.store.selectedSection = .images
        let request = Task { await fixture.store.retryResources() }
        try await waitUntil { await fixture.runner.isHoldingImages }
        fixture.store.selectedContext = "local-b"
        await fixture.runner.releaseImages()
        await request.value
        #expect(!fixture.store.isLoadingResources)
        #expect(fixture.store.resourceError == nil)
        #expect(fixture.store.images.isEmpty)
    }

    @Test
    func lateInspectionFailureCannotReplaceAnotherContextsStatus() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        await fixture.store.start()
        try await waitUntil { await fixture.runner.inventoryReads >= 2 && !fixture.store.isRefreshing }
        fixture.store.selectedContainerID = try #require(fixture.store.containers.first).id
        await fixture.runner.holdInspection()
        let request = Task { await fixture.store.retryInspection() }
        try await waitUntil { await fixture.runner.isHoldingInspection }
        #expect(fixture.store.isLoadingInspection)
        fixture.store.selectedContext = "local-b"
        await fixture.runner.releaseInspection()
        await request.value
        #expect(fixture.store.inspectionError == nil)
        #expect(!fixture.store.isLoadingInspection)
        #expect(fixture.store.inspection == nil)
    }

    @Test
    func logFailuresAreSeparateFromSearchableOutputAndRetryRecovers() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        await fixture.store.start()
        try await waitUntil { await fixture.runner.inventoryReads >= 2 && !fixture.store.isRefreshing }
        fixture.store.selectedContainerID = try #require(fixture.store.containers.first).id
        await fixture.runner.failLogs(true)
        fixture.store.retryLogs()
        try await waitUntil { fixture.store.logStreamState == .failed }
        #expect(fixture.store.logError?.contains("fixture log failure") == true)
        #expect(fixture.store.logText == "output before interruption\n")
        #expect(!fixture.store.logText.contains("fixture log failure"))
        await fixture.runner.failLogs(false)
        fixture.store.retryLogs()
        try await waitUntil { fixture.store.logStreamState == .following && fixture.store.logText == "fresh output\n" }
        #expect(fixture.store.logError == nil)
        fixture.store.closeDetail()
        #expect(fixture.store.logStreamState == .idle)
        #expect(fixture.store.logError == nil)
    }

    @Test
    func hidingStoppedContainersKeepsPausedRestartingAndUnknownStatesVisible() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.store.preferences.showStopped = false
        fixture.store.containers = ContainerState.allCases.enumerated().map { index, state in
            DockerContainer(id: String(index), name: state.rawValue, image: "fixture", state: state)
        }
        let visible = Set(fixture.store.groups.flatMap(\.containers).map(\.state))
        #expect(visible.contains(.running))
        #expect(visible.contains(.paused))
        #expect(visible.contains(.restarting))
        #expect(visible.contains(.unknown), "An unknown state must remain visible for diagnosis.")
        #expect(!visible.contains(.created))
        #expect(!visible.contains(.exited))
        #expect(!visible.contains(.dead))
    }

    @Test
    func hidingMainWindowPausesDetailStreamsWithoutLosingSelectionOrBuffer() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        await fixture.store.start()
        try await waitUntil { await fixture.runner.inventoryReads >= 2 && !fixture.store.isRefreshing }
        fixture.store.setApplicationActive(true)
        fixture.store.setMetricsVisible(true)
        fixture.store.selectedContainerID = try #require(fixture.store.containers.first).id
        fixture.store.retryLogs()
        try await waitUntil {
            let counts = await fixture.runner.streamCounts()
            return counts.stats == 1 && counts.logs == 1
        }
        let selected = fixture.store.selectedContainerID
        let text = fixture.store.logText
        let statsRequests = await fixture.runner.statsStreamRequests
        let logRequests = await fixture.runner.logStreamRequests
        fixture.store.setMainWindowVisible(false)
        try await waitUntil {
            let counts = await fixture.runner.streamCounts()
            return counts.stats == 0 && counts.logs == 0
        }
        #expect(fixture.store.selectedContainerID == selected)
        #expect(fixture.store.logText == text)
        #expect(fixture.store.logStreamState == .paused)
        fixture.store.setMetricsVisible(false)
        fixture.store.setMetricsVisible(true)
        fixture.store.retryLogs()
        #expect(await fixture.runner.statsStreamRequests == statsRequests)
        #expect(await fixture.runner.logStreamRequests == logRequests)
        #expect(await fixture.runner.activeEventStreams == 1, "Docker events can stay connected while the main window is hidden.")
        fixture.store.setMainWindowVisible(true)
        try await waitUntil {
            let counts = await fixture.runner.streamCounts()
            return counts.statsRequests == statsRequests + 1 && counts.logRequests == logRequests + 1
                && counts.stats == 1 && counts.logs == 1
        }
        #expect(fixture.store.selectedContainerID == selected)
        #expect(fixture.store.logStreamState == .following)
    }

    private func makeFixture() throws -> FailureFixture {
        let domain = "dev.dockey.failure-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let runner = FailureRunner()
        let client = DockerClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"), runner: runner)
        return FailureFixture(store: AppStore(defaults: defaults, client: client), runner: runner,
            defaults: defaults, domain: domain)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<300 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for fixture state")
        throw CocoaError(.coderInvalidValue)
    }
}

@MainActor
private struct FailureFixture {
    let store: AppStore
    let runner: FailureRunner
    let defaults: UserDefaults
    let domain: String
    func close() {
        store.shutdown()
        defaults.removePersistentDomain(forName: domain)
    }
}

private actor FailureRunner: CommandRunning {
    private let id = String(repeating: "a", count: 64)
    private(set) var inventoryReads = 0
    private(set) var statsStreamRequests = 0
    private(set) var logStreamRequests = 0
    private var streamKinds: [UUID: String] = [:]
    var activeStatsStreams: Int { streamKinds.values.filter { $0 == "stats" }.count }
    var activeLogStreams: Int { streamKinds.values.filter { $0 == "logs" }.count }
    var activeEventStreams: Int { streamKinds.values.filter { $0 == "events" }.count }
    func streamCounts() -> (stats: Int, logs: Int, statsRequests: Int, logRequests: Int) {
        (activeStatsStreams, activeLogStreams, statsStreamRequests, logStreamRequests)
    }
    private var inspectionFails = false
    private var imagesFail = false
    private var logsFail = false
    private var shouldHoldImages = false
    private var shouldHoldInspection = false
    private var heldImages: CheckedContinuation<CommandOutput, Error>?
    private var heldInspection: CheckedContinuation<CommandOutput, Error>?
    private var continuations: [UUID: AsyncThrowingStream<String, Error>.Continuation] = [:]
    var isHoldingImages: Bool { heldImages != nil }
    var isHoldingInspection: Bool { heldInspection != nil }
    func failInspection(_ value: Bool) { inspectionFails = value }
    func failImages(_ value: Bool) { imagesFail = value }
    func failLogs(_ value: Bool) { logsFail = value }
    func holdImages() { shouldHoldImages = true }
    func holdInspection() { shouldHoldInspection = true }
    func releaseImages() {
        heldImages?.resume(throwing: DockerError.commandFailed("old context image failure"))
        heldImages = nil
    }
    func releaseInspection() {
        heldInspection?.resume(throwing: DockerError.commandFailed("old context inspection failure"))
        heldInspection = nil
    }

    func run(_ request: CommandRequest) async throws -> CommandOutput {
        let args = request.arguments
        if args.starts(with: ["context", "ls"]) {
            return CommandOutput(stdout: """
                {"Name":"local-a","DockerEndpoint":"unix:///tmp/a.sock","Current":true}
                {"Name":"local-b","DockerEndpoint":"unix:///tmp/b.sock","Current":false}
                """)
        }
        if args.starts(with: ["context", "inspect"]) { return CommandOutput(stdout: "\"unix:///tmp/a.sock\"") }
        if args.contains("info") { return CommandOutput(stdout: "{\"NCPU\":2,\"MemTotal\":1024}") }
        if args.contains("container"), args.contains("ls") {
            inventoryReads += 1
            return CommandOutput(stdout: id + "\n")
        }
        if args.contains("container"), args.contains("inspect") {
            if shouldHoldInspection {
                shouldHoldInspection = false
                return try await withCheckedThrowingContinuation { heldInspection = $0 }
            }
            if inspectionFails { throw DockerError.commandFailed("fixture inspection failure") }
            return CommandOutput(stdout: """
                [{"Id":"\(id)","Name":"/fixture","Config":{"Image":"redis:latest","Labels":{}},"State":{"Status":"running"},"Mounts":[{"Type":"volume","Name":"data","Source":"/data","Destination":"/data"}]}]
                """)
        }
        if args.contains("image") {
            if shouldHoldImages {
                shouldHoldImages = false
                return try await withCheckedThrowingContinuation { heldImages = $0 }
            }
            if imagesFail { throw DockerError.commandFailed("fixture image failure") }
            return CommandOutput(stdout: "{\"ID\":\"sha256:abc\",\"Repository\":\"redis\",\"Tag\":\"latest\"}")
        }
        if args.contains("volume") { return CommandOutput(stdout: "{\"Name\":\"data\",\"Driver\":\"local\"}") }
        return CommandOutput()
    }

    nonisolated func stream(_ request: CommandRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let token = UUID()
            let registration = Task { await register(request, continuation: continuation, token: token) }
            continuation.onTermination = { @Sendable _ in
                registration.cancel()
                Task { await self.remove(token) }
            }
        }
    }

    private func register(_ request: CommandRequest, continuation: AsyncThrowingStream<String, Error>.Continuation,
        token: UUID) {
        guard !Task.isCancelled else { return }
        let kind = request.arguments.contains("logs") ? "logs" : request.arguments.contains("stats") ? "stats" : "events"
        if kind == "stats" { statsStreamRequests += 1 }
        if kind == "logs" { logStreamRequests += 1 }
        if request.arguments.contains("logs") {
            if logsFail {
                continuation.yield("output before interruption\n")
                continuation.finish(throwing: DockerError.commandFailed("fixture log failure"))
                return
            }
            continuation.yield("fresh output\n")
        }
        continuations[token] = continuation
        streamKinds[token] = kind
    }
    private func remove(_ token: UUID) {
        continuations.removeValue(forKey: token)
        streamKinds.removeValue(forKey: token)
    }
}
