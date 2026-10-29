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

    /// Reads `docker system df --verbose` JSON into usage totals and cleanup candidates.
    static func storage(_ text: String) throws -> StorageReport {
        let root = try object(text.trimmingCharacters(in: .whitespacesAndNewlines), operation: "disk usage")
        func rows(_ key: String) -> [[String: Any]] { root[key] as? [[String: Any]] ?? [] }
        var usage: [StorageUsage] = []
        var candidates: [CleanupCandidate] = []

        // One image ID can appear once per repository tag; size and container counts belong to the image.
        var images: [String: (tags: [String], containers: Int?, row: [String: Any])] = [:]
        var imageOrder: [String] = []
        for row in rows("Images") {
            guard let id = row["ID"] as? String, !id.isEmpty else { continue }
            let repository = row["Repository"] as? String ?? "<none>"
            let tag = row["Tag"] as? String ?? "<none>"
            if images[id] == nil {
                imageOrder.append(id)
                images[id] = ([], integer(row["Containers"]), row)
            }
            if repository != "<none>" {
                images[id]?.tags.append(tag == "<none>" ? repository : "\(repository):\(tag)")
            }
        }
        for id in imageOrder {
            guard let image = images[id], let containers = image.containers, containers == 0 else { continue }
            let dangling = image.tags.isEmpty
            let shortID = String(id.replacingOccurrences(of: "sha256:", with: "").prefix(12))
            candidates.append(
                CleanupCandidate(
                    kind: dangling ? .danglingImage : .unusedImage, identifier: id,
                    name: dangling ? "<none> · \(shortID)" : image.tags.joined(separator: ", "),
                    detail: joined(
                        dangling ? nil : shortID, (image.row["CreatedSince"] as? String).map { "Created \($0)" }),
                    bytes: size(image.row["UniqueSize"]) ?? size(image.row["Size"]),
                    // Removing an image ID with several tags fails; untag each reference instead.
                    removalArguments: ["image", "rm", "--"] + (dangling ? [id] : image.tags)))
        }
        usage.append(
            StorageUsage(
                category: .images, count: imageOrder.count,
                activeCount: imageOrder.filter { (images[$0]?.containers ?? 0) > 0 }.count, bytes: nil))

        let containers = rows("Containers")
        var containerBytes: UInt64 = 0
        var activeContainers = 0
        for row in containers {
            let bytes = size(row["Size"])
            containerBytes &+= bytes ?? 0
            let state = ContainerState(rawValue: row["State"] as? String ?? "") ?? .unknown
            if [.running, .paused, .restarting].contains(state) { activeContainers += 1 }
            guard [.exited, .created, .dead].contains(state), let id = row["ID"] as? String, !id.isEmpty else {
                continue
            }
            candidates.append(
                CleanupCandidate(
                    kind: .stoppedContainer, identifier: id, name: row["Names"] as? String ?? String(id.prefix(12)),
                    detail: joined(row["Image"] as? String, row["Status"] as? String),
                    bytes: bytes, project: labels(row["Labels"])["com.docker.compose.project"],
                    removalArguments: ["container", "rm", "--", id]))
        }
        usage.append(
            StorageUsage(
                category: .containers, count: containers.count, activeCount: activeContainers, bytes: containerBytes))

        let volumes = rows("Volumes")
        var volumeBytes: UInt64 = 0
        var activeVolumes = 0
        for row in volumes {
            let bytes = size(row["Size"])
            volumeBytes &+= bytes ?? 0
            guard let name = row["Name"] as? String, !name.isEmpty, let links = integer(row["Links"]) else { continue }
            if links > 0 {
                activeVolumes += 1
                continue
            }
            let tags = labels(row["Labels"])
            let anonymous =
                tags["com.docker.volume.anonymous"] != nil
                || (name.count == 64 && name.allSatisfy { $0.isHexDigit && !$0.isUppercase })
            candidates.append(
                CleanupCandidate(
                    kind: anonymous ? .anonymousVolume : .namedVolume, identifier: name,
                    name: anonymous ? String(name.prefix(12)) : name,
                    detail: joined(
                        row["Driver"] as? String, tags["com.docker.compose.volume"].map { "Compose volume \($0)" }),
                    bytes: bytes, project: tags["com.docker.compose.project"],
                    removalArguments: ["volume", "rm", "--", name]))
        }
        usage.append(
            StorageUsage(category: .volumes, count: volumes.count, activeCount: activeVolumes, bytes: volumeBytes))

        let cache = rows("BuildCache")
        var cacheBytes: UInt64 = 0
        var activeCache = 0
        for row in cache {
            let bytes = size(row["Size"])
            cacheBytes &+= bytes ?? 0
            if boolean(row["InUse"]) {
                activeCache += 1
                continue
            }
            guard let id = row["ID"] as? String, !id.isEmpty else { continue }
            let type = (row["CacheType"] ?? row["Type"]) as? String
            let description = (row["Description"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(120)) }
            candidates.append(
                CleanupCandidate(
                    kind: .buildCache, identifier: id, name: description ?? type ?? String(id.prefix(12)),
                    detail: joined(
                        description == nil ? nil : type, (row["LastUsedSince"] as? String).map { "Last used \($0)" }),
                    bytes: bytes))
        }
        usage.append(
            StorageUsage(category: .buildCache, count: cache.count, activeCount: activeCache, bytes: cacheBytes))

        candidates.sort { lhs, rhs in
            lhs.bytes ?? 0 == rhs.bytes ?? 0
                ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                : lhs.bytes ?? 0 > rhs.bytes ?? 0
        }
        return StorageReport(usage: usage, candidates: candidates)
    }

    /// Docker renders labels in verbose disk usage as `key=value,key=value`.
    private static func labels(_ value: Any?) -> [String: String] {
        if let dictionary = value as? [String: String] { return dictionary }
        guard let text = value as? String else { return [:] }
        return text.split(separator: ",").reduce(into: [:]) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first, !key.isEmpty else { return }
            result[String(key)] = parts.count > 1 ? String(parts[1]) : ""
        }
    }

    private static func size(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.int64Value >= 0 ? number.uint64Value : nil }
        return (value as? String).flatMap(ByteSize.parse)
    }

    private static func integer(_ value: Any?) -> Int? {
        let number = (value as? NSNumber)?.intValue ?? (value as? String).flatMap { Int($0) }
        return number.flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func boolean(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        return (value as? String)?.lowercased() == "true"
    }

    private static func joined(_ parts: String?...) -> String {
        parts.compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
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
