import Foundation

enum DockerParsing {
    static func object(_ text: String, operation: String) throws -> [String: Any] {
        guard let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw DockerError.invalidResponse(operation)
        }
        return object
    }

    static func array(_ text: String, operation: String) throws -> [[String: Any]] {
        guard let data = text.data(using: .utf8),
            let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            throw DockerError.invalidResponse(operation)
        }
        return array
    }

    static func lines(_ text: String, operation: String) throws -> [[String: Any]] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return [] }
        if clean.hasPrefix("[") { return try array(clean, operation: operation) }
        return try clean.split(whereSeparator: \.isNewline).map { try object(String($0), operation: operation) }
    }

    static func containers(_ text: String) throws -> [DockerContainer] {
        try array(text, operation: "container inspection").map { item in
            guard let id = item["Id"] as? String, !id.isEmpty,
                let rawName = item["Name"] as? String, !rawName.isEmpty
            else {
                throw DockerError.invalidResponse("container inspection")
            }
            let config = item["Config"] as? [String: Any] ?? [:]
            let state = item["State"] as? [String: Any] ?? [:]
            let labels = config["Labels"] as? [String: String] ?? [:]
            let health = state["Health"] as? [String: Any]
            let containerState = ContainerState(rawValue: state["Status"] as? String ?? "") ?? .unknown
            var status = containerState.label
            if containerState == .exited {
                if state["OOMKilled"] as? Bool == true {
                    status = "Stopped · out of memory"
                } else if let code = state["ExitCode"] as? Int {
                    status = "Exited (\(code))"
                }
            }
            return DockerContainer(
                id: id, name: rawName.hasPrefix("/") ? String(rawName.dropFirst()) : rawName,
                image: config["Image"] as? String ?? "Unknown image", state: containerState,
                health: (health?["Status"] as? String).flatMap(ContainerHealth.init(rawValue:)),
                project: nonempty(labels["com.docker.compose.project"]),
                service: nonempty(labels["com.docker.compose.service"]), ports: ports(item),
                createdAt: item["Created"] as? String ?? "", status: status)
        }
    }

    static func ports(_ item: [String: Any]) -> [PortBinding] {
        let settings = item["NetworkSettings"] as? [String: Any] ?? [:]
        let mappings = settings["Ports"] as? [String: Any] ?? [:]
        var result: [PortBinding] = []
        for (key, value) in mappings {
            let segments = key.split(separator: "/", maxSplits: 1)
            guard let first = segments.first, let port = Int(first), (1...65_535).contains(port),
                let bindings = value as? [[String: String]]
            else { continue }
            let transport = segments.count > 1 ? String(segments[1]) : "tcp"
            for binding in bindings {
                guard let host = Int(binding["HostPort"] ?? ""), (1...65_535).contains(host) else { continue }
                result.append(
                    PortBinding(
                        hostIP: binding["HostIp"] ?? "127.0.0.1", hostPort: host,
                        containerPort: port, transport: transport))
            }
        }
        return Array(Set(result.map(\.id))).sorted().compactMap { id in result.first { $0.id == id } }
    }

    static func stats(_ text: String) throws -> [ContainerStats] {
        try lines(text, operation: "container stats").compactMap { item in
            guard let id = item["ID"] as? String, !id.isEmpty else { return nil }
            return ContainerStats(
                id: id, cpuPercent: percent(item["CPUPerc"]),
                memoryUsage: (item["MemUsage"] as? String ?? "—").components(separatedBy: "/")[0].trimmingCharacters(
                    in: .whitespaces),
                memoryPercent: percent(item["MemPerc"]),
                networkIO: item["NetIO"] as? String ?? "—", blockIO: item["BlockIO"] as? String ?? "—")
        }
    }

    static func event(_ line: String) throws -> DockerEvent {
        let item = try object(line, operation: "Docker event")
        let actor = item["Actor"] as? [String: Any]
        guard let type = item["Type"] as? String, !type.isEmpty,
            let action = (item["Action"] ?? item["status"]) as? String, !action.isEmpty,
            let id = (actor?["ID"] ?? item["ID"] ?? item["id"]) as? String, !id.isEmpty
        else { throw DockerError.invalidResponse("Docker event") }
        let seconds: Double?
        if let nanos = item["timeNano"] as? NSNumber {
            seconds = nanos.doubleValue / 1_000_000_000
        } else {
            seconds = (item["time"] as? NSNumber)?.doubleValue
        }
        let timestamp = seconds.flatMap { $0.isFinite && $0 >= 0 ? Date(timeIntervalSince1970: $0) : nil }
        return DockerEvent(type: type, action: action, actorID: id, timestamp: timestamp)
    }

    static func streamStats(_ line: String) throws -> ContainerStats {
        guard let stat = try stats(line).first else {
            throw DockerError.invalidResponse("container stats")
        }
        return stat
    }

    static func inspection(_ text: String) throws -> ContainerInspection {
        guard let raw = try array(text, operation: "container inspection").first else {
            throw DockerError.invalidResponse("container inspection")
        }
        let config = raw["Config"] as? [String: Any] ?? [:]
        let environment = config["Env"] as? [String] ?? []
        let keys = environment.map {
            String($0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0])
        }.sorted()
        let mounts = (raw["Mounts"] as? [[String: Any]] ?? []).map { mount in
            "\(mount["Type"] as? String ?? "mount"): \(mount["Source"] as? String ?? "—") → \(mount["Destination"] as? String ?? "—") (\((mount["RW"] as? Bool ?? false) ? "read/write" : "read-only"))"
        }
        let safe = redact(raw)
        let data = try JSONSerialization.data(
            withJSONObject: safe, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return ContainerInspection(json: String(decoding: data, as: UTF8.self), environmentKeys: keys, mounts: mounts)
    }

    private static func redact(_ value: Any, path: [String] = []) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                let key = entry.key
                let normalized = key.lowercased().filter(\.isLetter)
                let isHealthHistoryOutput =
                    normalized == "output"
                    && path.suffix(3).map { $0.lowercased() } == ["state", "health", "log"]
                let isOpaqueDriverOptions =
                    ["driveropts", "driveroptions"].contains(normalized)
                    || (normalized == "options"
                        && (path.last?.lowercased() == "driverconfig"
                            || dictionary.keys.contains { $0.lowercased() == "driver" }))
                if normalized == "labels" || isOpaqueDriverOptions {
                    // Opaque values may contain URL credentials or CSV mount options even
                    // when their keys are innocuous. Retain keys/shape without their values.
                    result[key] = redactOpaqueValues(entry.value)
                } else if ["password", "secret", "token", "credential", "authorization", "privatekey", "apikey"].contains(
                    where: normalized.contains)
                    || ["auth", "args", "cmd", "entrypoint"].contains(normalized)
                    || (path.last?.lowercased() == "healthcheck" && normalized == "test")
                    || isHealthHistoryOutput
                {
                    result[key] = "<redacted>"
                } else if normalized == "env", let items = entry.value as? [String] {
                    result[key] = items.map { item in
                        let key = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                        return "\(key)=<redacted>"
                    }
                } else {
                    result[key] = redact(entry.value, path: path + [key])
                }
            }
        }
        if let array = value as? [Any] { return array.map { redact($0, path: path) } }
        return value
    }

    private static func redactOpaqueValues(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] { return dictionary.mapValues(redactOpaqueValues) }
        if let array = value as? [Any] { return array.map(redactOpaqueValues) }
        return "<redacted>"
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func percent(_ value: Any?) -> Double {
        let number =
            Double(
                (value as? String ?? "0").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
            ?? 0
        return number.isFinite ? max(0, number) : 0
    }
}
