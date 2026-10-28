import DockeyCore
import Foundation
import Testing

@testable import Dockey

@Suite("Application state")
@MainActor
struct AppStoreTests {
    @Test
    func testContextSelectionInvalidatesOldRowsBeforeAnyAwait() async throws {
        let domain = "dev.dockey.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let runner = StoreFixtureRunner()
        let client = DockerClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"), runner: runner)
        let store = AppStore(defaults: defaults, client: client)
        defer { store.shutdown() }
        await store.start()
        #expect(store.isConnected)
        #expect(store.selectedContext == "local-a")
        let oldRows = store.containers
        #expect(oldRows.count == 1)

        store.selectedContext = "local-b"
        #expect(!store.isConnected)
        #expect(store.containers.isEmpty)
        #expect(store.selectedContainerID == nil)
        store.perform(.stop, on: oldRows)
        #expect(store.operationError != nil)
        let mutations = await runner.mutationCount
        #expect(mutations == 0, "Stale rows must never be sent to a newly selected context.")
    }

    @Test
    func testExecutableChangeInvalidatesConnectionSynchronously() async throws {
        let domain = "dev.dockey.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let runner = StoreFixtureRunner()
        let client = DockerClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"), runner: runner)
        let store = AppStore(defaults: defaults, client: client)
        defer { store.shutdown() }
        await store.start()
        #expect(store.isConnected)
        store.preferences.dockerExecutable = "/nonexistent/dockey-test/docker"
        store.savePreferences()
        #expect(!store.isConnected)
        #expect(store.containers.isEmpty)
    }

    @Test
    func testDemoDoesNotUseInjectedDockerClientOrPersistPreferences() async throws {
        let domain = "dev.dockey.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let runner = StoreFixtureRunner()
        let client = DockerClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"), runner: runner)
        let store = AppStore(demo: true, appearance: "dark", defaults: defaults, client: client)
        defer { store.shutdown() }
        await store.start()
        #expect(store.isConnected)
        #expect(!store.containers.isEmpty)
        store.preferences.appearance = "light"
        store.savePreferences()
        await store.refresh()
        let requests = await runner.requestCount
        #expect(requests == 0)
        #expect(defaults.data(forKey: "appPreferences.v1") == nil)
        #expect(defaults.string(forKey: "selectedContext.v1") == nil)
    }

    @Test
    func testInvalidPreferenceValuesAreNormalized() {
        var value = AppPreferences()
        value.appearance = "invalid"
        value.density = "invalid"
        value.logFontSize = .infinity
        value.stopTimeout = -20
        value.logTail = Int.max
        value.normalize()
        #expect(value.appearance == "system")
        #expect(value.density == "compact")
        #expect(value.logFontSize == 12)
        #expect(value.stopTimeout == 1)
        #expect(value.logTail == 10_000)
    }
}

private actor StoreFixtureRunner: CommandRunning {
    private(set) var mutationCount = 0
    private(set) var requestCount = 0
    private let id = String(repeating: "a", count: 64)

    func run(_ request: CommandRequest) async throws -> CommandOutput {
        requestCount += 1
        let args = request.arguments
        if args.starts(with: ["context", "ls"]) {
            return CommandOutput(
                stdout: """
                    {"Name":"local-a","DockerEndpoint":"unix:///tmp/dockey-a.sock","Current":true}
                    {"Name":"local-b","DockerEndpoint":"unix:///tmp/dockey-b.sock","Current":false}
                    """)
        }
        if args.starts(with: ["context", "inspect"]) { return CommandOutput(stdout: "\"unix:///tmp/dockey-a.sock\"") }
        if args.contains("info") {
            return CommandOutput(
                stdout:
                    "{\"ServerVersion\":\"fixture\",\"Architecture\":\"arm64\",\"OperatingSystem\":\"test\",\"NCPU\":2,\"MemTotal\":1073741824}"
            )
        }
        if args.contains("container"), args.contains("ls") { return CommandOutput(stdout: id + "\n") }
        if args.contains("container"), args.contains("inspect") {
            return CommandOutput(
                stdout:
                    "[{\"Id\":\"\(id)\",\"Name\":\"/fixture-api\",\"Config\":{\"Image\":\"fixture:latest\",\"Labels\":{}},\"State\":{\"Status\":\"running\"}}]"
            )
        }
        if args.contains("stats") { return CommandOutput() }
        if args.contains("container"), args.contains(where: { ["start", "stop", "restart"].contains($0) }) {
            mutationCount += 1
        }
        return CommandOutput()
    }

    nonisolated func stream(_ request: CommandRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
