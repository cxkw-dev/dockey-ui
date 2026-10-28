import Darwin
import DockeyCore
import Foundation

/// Opt-in integration probe. Lifecycle checks are restricted to explicitly labelled disposable fixtures.
@main
struct DockeySmoke {
    static func main() async {
        do { try await run() } catch {
            FileHandle.standardError.write(Data("Dockey smoke test failed: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let arguments = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard let context = value("--context"), let id = value("--container") else {
            throw SmokeError("Usage: swift run DockeySmoke --context CONTEXT --container FIXTURE_ID [--report PATH]")
        }
        let client = DockerClient()
        defer { client.cancelPendingCommands() }
        let contexts = try await client.contexts()
        guard contexts.contains(where: { $0.name == context && $0.isLocal }) else {
            throw SmokeError("A verified local context is required.")
        }
        let containers = try await client.containers(context: context)
        guard let fixture = containers.first(where: { $0.id == id }), fixture.name.hasPrefix("dockey-smoke-") else {
            throw SmokeError("Only an existing dockey-smoke- fixture can be used.")
        }
        let groups = ContainerGrouping.groups(containers: containers, context: context)
        guard
            groups.contains(where: {
                $0.isCompose && $0.name == "dockey-smoke" && $0.containers.contains(where: { $0.id == id })
            })
        else {
            throw SmokeError("The fixture must be discovered inside the dockey-smoke Compose-label group.")
        }
        let inspection = try await client.inspect(containerID: id, context: context)
        let object = try JSONSerialization.jsonObject(with: Data(inspection.json.utf8)) as? [String: Any]
        let config = object?["Config"] as? [String: Any]
        let labels = config?["Labels"] as? [String: String]
        guard labels?["dev.dockey.smoke"] == "true" else {
            throw SmokeError("Fixture must have dev.dockey.smoke=true.")
        }
        let info = try await client.engineInfo(context: context)
        _ = try await client.images(context: context)
        _ = try await client.volumes(context: context)
        _ = try await client.networks(context: context)
        _ = try await client.stats(context: context)
        var passed = [
            "local context discovery", "container inspection and Compose grouping", "engine info", "images", "volumes",
            "networks", "resource stats",
        ]
        for action in [ContainerAction.stop, .start, .restart] {
            let result = try await client.perform(action, containerIDs: [id], context: context, stopTimeout: 2)
            guard result.succeeded else { throw SmokeError(result.results.map(\.message).joined(separator: "; ")) }
            let state = try await client.containers(context: context).first(where: { $0.id == id })?.state
            guard state == (action == .stop ? .exited : .running) else {
                throw SmokeError("Unexpected state after \(action.label).")
            }
            passed.append("fixture \(action.rawValue)")
        }
        let logs = try await client.logs(containerID: id, context: context, tail: 20)
        guard logs.contains("dockey-smoke-ready") else { throw SmokeError("Fixture log marker was missing.") }
        passed.append("log tail")
        let streamTask = Task {
            let stream = await client.logStream(containerID: id, context: context, tail: 10)
            for try await chunk in stream where chunk.contains("dockey-smoke-ready") { return true }
            return false
        }
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(15))
            streamTask.cancel()
        }
        let streamed = try await streamTask.value
        timeoutTask.cancel()
        guard streamed else { throw SmokeError("Log stream did not deliver the fixture marker.") }
        passed.append("cancellable log stream")
        let report: [String: Any] = [
            "passed": true,
            "engineVersion": info.serverVersion,
            "architecture": info.architecture,
            "checks": passed,
            "scope":
                "Read-only discovery plus lifecycle operations on one labelled disposable fixture. No existing workloads were modified.",
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if let output = value("--report") { try data.write(to: URL(fileURLWithPath: output), options: .atomic) }
        print(String(decoding: data, as: UTF8.self))
    }
}

struct SmokeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
