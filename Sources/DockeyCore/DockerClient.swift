import Foundation

/// A local-only Docker CLI adapter. Every engine operation names its context explicitly.
/// There are intentionally no arbitrary commands, pruning, deletion, or Compose-file execution APIs.
public actor DockerClient {
    private let configuredExecutable: URL?
    private let runner: any CommandRunning
    private var executable: URL?

    public init(executableURL: URL? = nil) {
        configuredExecutable = executableURL
        runner = ProcessCommandRunner()
    }

    public init(executableURL: URL?, runner: any CommandRunning) {
        configuredExecutable = executableURL
        self.runner = runner
    }

    /// Synchronous shutdown for this client's CLI children; Docker Engine keeps running.
    public nonisolated func cancelPendingCommands() { runner.cancelAll() }

    public func resolvedExecutable() async throws -> URL {
        if let executable { return executable }
        let manager = FileManager.default
        let candidates: [URL]
        if let configuredExecutable {
            candidates = [configuredExecutable]
        } else {
            let standard = [
                "/opt/homebrew/bin/docker", "/usr/local/bin/docker",
                manager.homeDirectoryForCurrentUser.appendingPathComponent(".docker/bin/docker").path,
            ]
            let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/docker" }
            candidates = (standard + paths).map { URL(fileURLWithPath: $0) }
        }
        for candidate in candidates {
            var directory: ObjCBool = false
            guard candidate.isFileURL, candidate.path.hasPrefix("/"),
                manager.fileExists(atPath: candidate.path, isDirectory: &directory), !directory.boolValue,
                manager.isExecutableFile(atPath: candidate.path)
            else { continue }
            let resolved = candidate.resolvingSymlinksInPath()
            executable = resolved
            return resolved
        }
        if let configuredExecutable { throw DockerError.invalidExecutable(configuredExecutable.path) }
        throw DockerError.executableNotFound
    }

    public func contexts() async throws -> [DockerContext] {
        let output = try await raw(["context", "ls", "--format", "{{json .}}"])
        return try DockerParsing.lines(output, operation: "context listing").compactMap { item in
            guard let name = item["Name"] as? String, !name.isEmpty else { return nil }
            return DockerContext(
                name: name, endpoint: item["DockerEndpoint"] as? String ?? "",
                isCurrent: item["Current"] as? Bool ?? false)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func containers(context: String) async throws -> [DockerContainer] {
        try await requireLocal(context)
        let output = try await raw(["--context", context, "container", "ls", "--all", "--quiet", "--no-trunc"])
        let ids = output.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !ids.isEmpty else { return [] }
        for id in ids { try validateContainerID(id) }
        var result: [DockerContainer] = []
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let inspected = try await raw(["--context", context, "container", "inspect", "--"] + batch)
            result += try DockerParsing.containers(inspected)
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func stats(context: String) async throws -> [ContainerStats] {
        try await requireLocal(context)
        return try DockerParsing.stats(
            await raw(
                [
                    "--context", context, "container", "stats", "--all", "--no-stream", "--no-trunc", "--format",
                    "{{json .}}",
                ], timeout: 12))
    }

    /// Persistent local-engine lifecycle events. There is no idle timeout or inventory polling.
    public func events(context: String, since: Date = Date()) async -> AsyncThrowingStream<DockerEvent, Error> {
        do {
            // Callers capture this before their reconciliation snapshot. Round down to
            // replay the opening second as well as events during validation/startup.
            let seconds = since.timeIntervalSince1970
            guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else {
                throw DockerError.invalidResponse("event replay timestamp")
            }
            let replayStart = String(Int(seconds.rounded(.down)))
            try await requireLocal(context)
            try Task.checkCancellation()
            let executable = try await resolvedExecutable()
            let arguments = [
                "--context", context, "events", "--since", replayStart,
                "--filter", "type=container", "--filter", "type=image",
                "--filter", "type=volume", "--filter", "type=network", "--format", "{{json .}}",
            ]
            return Self.decodedStream(
                runner.stream(
                    CommandRequest(
                        executableURL: executable, arguments: arguments, timeout: 0, streamStderr: false)),
                parse: DockerParsing.event)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    public func eventStream(context: String, since: Date = Date()) async -> AsyncThrowingStream<DockerEvent, Error> {
        await events(context: context, since: since)
    }

    /// One persistent CLI connection yields individual metrics as Docker publishes them.
    public func statsStream(context: String) async -> AsyncThrowingStream<ContainerStats, Error> {
        do {
            try await requireLocal(context)
            try Task.checkCancellation()
            let executable = try await resolvedExecutable()
            return Self.decodedStream(
                runner.stream(
                    CommandRequest(
                        executableURL: executable,
                        arguments: [
                            "--context", context, "container", "stats", "--all", "--no-trunc", "--format", "{{json .}}",
                        ], timeout: 0, streamStderr: false)),
                parse: DockerParsing.streamStats)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    private nonisolated static func decodedStream<Value: Sendable>(
        _ source: AsyncThrowingStream<String, Error>,
        parse: @escaping @Sendable (String) throws -> Value
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
            let task = Task {
                var framer = DockerStreamFramer()
                do {
                    for try await chunk in source {
                        try Task.checkCancellation()
                        for line in try framer.append(chunk) {
                            switch continuation.yield(try parse(line)) {
                            case .enqueued: break
                            case .dropped: throw DockerError.outputLimitExceeded
                            case .terminated: throw CancellationError()
                            @unknown default: throw DockerError.outputLimitExceeded
                            }
                        }
                    }
                    for line in try framer.finish() {
                        switch continuation.yield(try parse(line)) {
                        case .enqueued: break
                        case .dropped: throw DockerError.outputLimitExceeded
                        case .terminated: throw CancellationError()
                        @unknown default: throw DockerError.outputLimitExceeded
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func images(context: String) async throws -> [ImageSummary] {
        try await requireLocal(context)
        let output = try await raw(["--context", context, "image", "ls", "--no-trunc", "--format", "{{json .}}"])
        return try DockerParsing.lines(output, operation: "image listing").compactMap { item in
            guard let imageID = item["ID"] as? String else { return nil }
            let repository = item["Repository"] as? String ?? "<none>"
            let tag = item["Tag"] as? String ?? "<none>"
            return ImageSummary(
                id: "\(imageID)|\(repository):\(tag)", repository: repository, tag: tag,
                size: item["Size"] as? String ?? "—", createdSince: item["CreatedSince"] as? String ?? "",
                imageID: imageID)
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public func volumes(context: String) async throws -> [VolumeSummary] {
        try await requireLocal(context)
        let output = try await raw(["--context", context, "volume", "ls", "--format", "{{json .}}"])
        return try DockerParsing.lines(output, operation: "volume listing").compactMap { item in
            guard let name = item["Name"] as? String else { return nil }
            return VolumeSummary(
                id: name, name: name, driver: item["Driver"] as? String ?? "",
                mountpoint: item["Mountpoint"] as? String ?? "")
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func networks(context: String) async throws -> [NetworkSummary] {
        try await requireLocal(context)
        let output = try await raw(["--context", context, "network", "ls", "--no-trunc", "--format", "{{json .}}"])
        return try DockerParsing.lines(output, operation: "network listing").compactMap { item in
            guard let id = item["ID"] as? String, let name = item["Name"] as? String else { return nil }
            return NetworkSummary(
                id: id, name: name, driver: item["Driver"] as? String ?? "",
                scope: item["Scope"] as? String ?? "")
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func engineInfo(context: String) async throws -> EngineInfo {
        try await requireLocal(context)
        let output = try await raw(["--context", context, "info", "--format", "{{json .}}"])
        let info = try DockerParsing.object(output, operation: "engine information")
        return EngineInfo(
            serverVersion: info["ServerVersion"] as? String ?? "Unknown",
            architecture: info["Architecture"] as? String ?? "Unknown",
            operatingSystem: info["OperatingSystem"] as? String ?? "Unknown",
            cpus: max(0, info["NCPU"] as? Int ?? 0),
            memoryBytes: (info["MemTotal"] as? NSNumber)?.uint64Value ?? 0)
    }

    public func perform(
        _ action: ContainerAction, containerIDs: [String], context: String,
        stopTimeout: Int = 10
    ) async throws -> OperationReport {
        // Validate the complete request before issuing even its first mutation.
        let ids = Array(Set(containerIDs)).sorted()
        for id in ids { try validateContainerID(id) }
        guard !ids.isEmpty else { return OperationReport(action: action, results: []) }
        try await requireLocal(context)
        var results: [OperationResult] = []
        for id in ids {
            try Task.checkCancellation()
            var arguments = ["--context", context, "container", action.rawValue]
            if action != .start { arguments += ["--timeout", String(min(120, max(1, stopTimeout)))] }
            arguments += ["--", id]
            do {
                _ = try await raw(arguments, timeout: Double(min(120, max(1, stopTimeout))) + 15)
                results.append(OperationResult(containerID: id, succeeded: true, message: "\(action.label) completed."))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                results.append(OperationResult(containerID: id, succeeded: false, message: error.localizedDescription))
            }
        }
        return OperationReport(action: action, results: results)
    }

    public func inspect(containerID: String, context: String) async throws -> ContainerInspection {
        try validateContainerID(containerID)
        try await requireLocal(context)
        return try DockerParsing.inspection(
            await raw(["--context", context, "container", "inspect", "--", containerID]))
    }

    public func logs(containerID: String, context: String, tail: Int = 1000, timestamps: Bool = true) async throws
        -> String
    {
        try validateContainerID(containerID)
        try await requireLocal(context)
        let executable = try await resolvedExecutable()
        let output = try await runner.run(
            CommandRequest(
                executableURL: executable,
                arguments: logArguments(
                    containerID: containerID, context: context, tail: tail, timestamps: timestamps, follow: false)))
        guard output.exitCode == 0 else { throw DockerError.commandFailed(String(output.stderr.prefix(2_048))) }
        // Docker writes a container's stderr log stream to the CLI's stderr pipe, even on success.
        return output.stdout + output.stderr
    }

    public func logStream(
        containerID: String, context: String, tail: Int = 1000,
        timestamps: Bool = true
    ) async -> AsyncThrowingStream<String, Error> {
        do {
            try validateContainerID(containerID)
            try await requireLocal(context)
            let executable = try await resolvedExecutable()
            return runner.stream(
                CommandRequest(
                    executableURL: executable,
                    arguments: logArguments(
                        containerID: containerID, context: context, tail: tail, timestamps: timestamps, follow: true),
                    timeout: 0))
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    private func requireLocal(_ context: String) async throws {
        guard !context.isEmpty, !context.contains("\0"), !context.contains("\n") else {
            throw DockerError.unknownContext(context)
        }
        let json = try await raw(["context", "inspect", "--format", "{{json .Endpoints.docker.Host}}", "--", context])
        guard let data = json.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
            let endpoint = try? JSONDecoder().decode(String.self, from: data)
        else {
            throw DockerError.invalidResponse("context endpoint")
        }
        guard DockerContext(name: context, endpoint: endpoint).isLocal else {
            throw DockerError.remoteContextUnsupported(context)
        }
    }

    private func raw(_ arguments: [String], timeout: TimeInterval = 20) async throws -> String {
        try Task.checkCancellation()
        let executable = try await resolvedExecutable()
        let output = try await runner.run(
            CommandRequest(executableURL: executable, arguments: arguments, timeout: timeout))
        guard output.exitCode == 0 else {
            throw DockerError.commandFailed(
                String(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_048)))
        }
        return output.stdout
    }

    private func validateContainerID(_ id: String) throws {
        guard (12...64).contains(id.count),
            id.allSatisfy({ $0.isASCII && ($0.isNumber || ("a"..."f").contains(String($0))) })
        else {
            throw DockerError.invalidContainerID
        }
    }

    private func logArguments(containerID: String, context: String, tail: Int, timestamps: Bool, follow: Bool)
        -> [String]
    {
        var arguments = ["--context", context, "container", "logs", "--tail", String(min(10_000, max(0, tail)))]
        if timestamps { arguments.append("--timestamps") }
        if follow { arguments.append("--follow") }
        arguments += ["--", containerID]
        return arguments
    }
}
