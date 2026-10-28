import Darwin
import Foundation
import Testing

@testable import DockeyCore

private final class StreamFixtureRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [CommandRequest] = []
    private var endpoints: [String]
    private let chunks: [String]
    private let streamError: DockerError?

    init(
        endpoints: [String] = ["unix:///tmp/dockey-stream-fixture.sock"],
        chunks: [String] = [], streamError: DockerError? = nil
    ) {
        self.endpoints = endpoints
        self.chunks = chunks
        self.streamError = streamError
    }

    var requests: [CommandRequest] { lock.withLock { recorded } }

    func run(_ request: CommandRequest) async throws -> CommandOutput {
        try lock.withLock {
            recorded.append(request)
            guard !endpoints.isEmpty else { throw DockerError.commandFailed("Unexpected fixture command") }
            let endpoint = endpoints.removeFirst()
            let data = try JSONEncoder().encode(endpoint)
            return CommandOutput(stdout: String(decoding: data, as: UTF8.self))
        }
    }

    func stream(_ request: CommandRequest) -> AsyncThrowingStream<String, Error> {
        lock.withLock { recorded.append(request) }
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish(throwing: streamError)
        }
    }
}

/// Only the stream subprocess is real; context validation uses a local fixture response.
private struct ProcessStreamFixtureRunner: CommandRunning {
    let processRunner = ProcessCommandRunner()
    func run(_ request: CommandRequest) async throws -> CommandOutput {
        CommandOutput(stdout: #""unix:///tmp/dockey-stream-fixture.sock""#)
    }
    func stream(_ request: CommandRequest) -> AsyncThrowingStream<String, Error> {
        processRunner.stream(
            CommandRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: [
                    "-c",
                    """
                    import json, os, time
                    print(json.dumps({'Type':'container','Action':'start','Actor':{'ID':str(os.getpid())}}),flush=True)
                    time.sleep(30)
                    """,
                ], timeout: 0, streamStderr: false))
    }
    func cancelAll() { processRunner.cancelAll() }
}

@Suite("Persistent local Docker streams", .timeLimit(.minutes(1)))
struct DockerStreamTests {
    private func client(_ runner: some CommandRunning) -> DockerClient {
        DockerClient(executableURL: URL(fileURLWithPath: "/bin/echo"), runner: runner)
    }

    @Test func eventFramesSpanChunksAndDiscardPrivateAttributes() async throws {
        let runner = StreamFixtureRunner(chunks: [
            #"{"Type":"container","Action":"sta"#,
            #"rt","Actor":{"ID":"fixture","Attributes":{"private":"fixture-private-value"}},"time":1,"timeNano":2000000000}"#
                + "\n",
            #"{"Type":"network","Action":"connect","Actor":{"ID":"fixture-network"},"time":3}"#,
        ])
        var events: [DockerEvent] = []
        let beforeSnapshot = Date(timeIntervalSince1970: 1_700_000_000.75)
        for try await event in await client(runner).events(context: "fixture", since: beforeSnapshot) {
            events.append(event)
        }
        #expect(events.count == 2)
        #expect(
            events.first
                == DockerEvent(
                    type: "container", action: "start", actorID: "fixture", timestamp: Date(timeIntervalSince1970: 2)))
        #expect(!String(reflecting: events).contains("fixture-private-value"))
        #expect(events.last?.id == "fixture-network")
        let requests = runner.requests
        #expect(requests.count == 2)
        #expect(
            requests[0].arguments == [
                "context", "inspect", "--format", "{{json .Endpoints.docker.Host}}", "--", "fixture",
            ])
        #expect(requests[1].arguments.prefix(3) == ["--context", "fixture", "events"])
        for type in ["container", "image", "volume", "network"] {
            #expect(requests[1].arguments.contains("type=\(type)"))
        }
        #expect(requests[1].arguments.contains("--since"))
        let replayFlag = try #require(requests[1].arguments.firstIndex(of: "--since"))
        #expect(requests[1].arguments[replayFlag + 1] == "1700000000")
        #expect(requests[1].timeout == 0)
        #expect(!requests[1].streamStderr)
    }

    @Test func statsHandleSplitAnsiSequencesAndTrailingFrame() async throws {
        let runner = StreamFixtureRunner(chunks: [
            "\u{1B}[", "2J\u{1B}[H" + #"{"ID":"first","CPUPerc":"12."#,
            #"5%","MemUsage":"10MiB / 1GiB","MemPerc":"1%"}"# + "\r\n\u{1B}]title",
            "\u{1B}", "\\" + #"{"ID":"second","CPUPerc":"2%","MemUsage":"2MiB / 1GiB"}"#,
        ])
        var stats: [ContainerStats] = []
        for try await stat in await client(runner).statsStream(context: "fixture") { stats.append(stat) }
        #expect(stats.map(\.id) == ["first", "second"])
        #expect(stats.first?.cpuPercent == 12.5)
        #expect(stats.first?.memoryUsage == "10MiB")
        let request = try #require(runner.requests.last)
        #expect(request.arguments.prefix(4) == ["--context", "fixture", "container", "stats"])
        #expect(!request.arguments.contains("--no-stream"))
        #expect(request.timeout == 0)
        #expect(!request.streamStderr)
    }

    @Test func remoteContextsCannotOpenEitherStream() async {
        for stats in [false, true] {
            let runner = StreamFixtureRunner(endpoints: ["ssh://fixture.example"])
            let docker = client(runner)
            do {
                if stats {
                    for try await _ in await docker.statsStream(context: "remote") {}
                } else {
                    for try await _ in await docker.events(context: "remote") {}
                }
                Issue.record("Remote stream was accepted")
            } catch { #expect(error as? DockerError == .remoteContextUnsupported("remote")) }
            #expect(runner.requests.count == 1)
        }
    }

    @Test func reopeningAlwaysRevalidatesTheEndpoint() async throws {
        let runner = StreamFixtureRunner(endpoints: ["unix:///tmp/dockey-fixture.sock", "tcp://fixture.example:2375"])
        let docker = client(runner)
        for try await _ in await docker.events(context: "fixture") {}
        do {
            for try await _ in await docker.statsStream(context: "fixture") {}
            Issue.record("Changed remote endpoint bypassed validation")
        } catch { #expect(error as? DockerError == .remoteContextUnsupported("fixture")) }
        #expect(runner.requests.filter { $0.arguments.first == "context" }.count == 2)
        #expect(runner.requests.filter { $0.arguments.first == "--context" }.count == 1)
    }

    @Test func malformedRecordsAndCliErrorsPropagate() async {
        let malformed = StreamFixtureRunner(chunks: ["not-json\n"])
        do {
            for try await _ in await client(malformed).events(context: "fixture") {}
            Issue.record("Malformed event was accepted")
        } catch { #expect(error as? DockerError == .invalidResponse("Docker event")) }
        let failed = StreamFixtureRunner(streamError: .commandFailed("fixture CLI failure"))
        do {
            for try await _ in await client(failed).statsStream(context: "fixture") {}
            Issue.record("CLI stream failure was hidden")
        } catch { #expect(error as? DockerError == .commandFailed("fixture CLI failure")) }
    }

    @Test func partialRecordsCannotGrowWithoutBound() {
        var framer = DockerStreamFramer()
        #expect(throws: DockerError.outputLimitExceeded) {
            try framer.append(String(repeating: "x", count: 65_537))
        }
    }

    @Test func cancellingConsumerTerminatesThePersistentCliProcess() async throws {
        let runner = ProcessStreamFixtureRunner()
        let docker = client(runner)
        let observed = AsyncStream<Int32>.makeStream()
        let task = Task {
            for try await event in await docker.events(context: "fixture") {
                if let pid = Int32(event.actorID) { observed.continuation.yield(pid) }
            }
        }
        defer {
            task.cancel()
            runner.cancelAll()
            observed.continuation.finish()
        }
        var iterator = observed.stream.makeAsyncIterator()
        let observedPID = await iterator.next()
        let pid = try #require(observedPID)
        #expect(kill(pid, 0) == 0)
        task.cancel()
        do { try await task.value } catch { #expect(error is CancellationError) }
        for _ in 0..<40 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(kill(pid, 0) != 0)
    }
}
