import Foundation

public struct DockerContext: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let endpoint: String
    public let isCurrent: Bool
    public var isLocal: Bool { endpoint.hasPrefix("unix:///") && endpoint.count > 8 }
    public init(name: String, endpoint: String, isCurrent: Bool = false) {
        self.name = name
        self.endpoint = endpoint
        self.isCurrent = isCurrent
    }
}

public enum ContainerState: String, Codable, Sendable, CaseIterable {
    case running, exited, created, paused, restarting, removing, dead, unknown
    public var label: String {
        switch self {
        case .exited: "Stopped"
        case .unknown: "Unknown"
        default: rawValue.capitalized
        }
    }
    public var isRunning: Bool { self == .running }
}

public enum ContainerHealth: String, Codable, Sendable { case healthy, unhealthy, starting }

public struct PortBinding: Identifiable, Sendable, Equatable {
    public let hostIP: String
    public let hostPort: Int
    public let containerPort: Int
    public let transport: String
    public var id: String { "\(hostIP):\(hostPort):\(containerPort)/\(transport)" }
    public var display: String { "\(hostPort):\(containerPort)\(transport == "tcp" ? "" : "/\(transport)")" }
    public init(hostIP: String = "127.0.0.1", hostPort: Int, containerPort: Int, transport: String = "tcp") {
        self.hostIP = hostIP
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.transport = transport
    }
}

public struct DockerContainer: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let image: String
    public let state: ContainerState
    public let health: ContainerHealth?
    public let project: String?
    public let service: String?
    public let ports: [PortBinding]
    public let createdAt: String
    public let status: String
    public var isRunning: Bool { state.isRunning }
    public var isUnhealthy: Bool { isRunning && health == .unhealthy }
    public init(
        id: String, name: String, image: String, state: ContainerState, health: ContainerHealth? = nil,
        project: String? = nil, service: String? = nil, ports: [PortBinding] = [],
        createdAt: String = "", status: String = ""
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.health = health
        self.project = project
        self.service = service
        self.ports = ports
        self.createdAt = createdAt
        self.status = status
    }
}

public struct ContainerStats: Identifiable, Sendable, Equatable {
    public let id: String
    public let cpuPercent: Double
    public let memoryUsage: String
    public let memoryPercent: Double
    public let networkIO: String
    public let blockIO: String
    public init(
        id: String, cpuPercent: Double, memoryUsage: String, memoryPercent: Double = 0,
        networkIO: String = "—", blockIO: String = "—"
    ) {
        self.id = id
        self.cpuPercent = cpuPercent
        self.memoryUsage = memoryUsage
        self.memoryPercent = memoryPercent
        self.networkIO = networkIO
        self.blockIO = blockIO
    }
}

public struct ContainerGroup: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let isCompose: Bool
    public let containers: [DockerContainer]
    public var runningCount: Int { containers.filter(\.isRunning).count }
    public var unhealthyCount: Int { containers.filter(\.isUnhealthy).count }
    public init(id: String, name: String, isCompose: Bool, containers: [DockerContainer]) {
        self.id = id
        self.name = name
        self.isCompose = isCompose
        self.containers = containers
    }
}

public enum ContainerGrouping {
    public static func groups(containers: [DockerContainer], context: String) -> [ContainerGroup] {
        let projects = Dictionary(grouping: containers.filter { $0.project?.isEmpty == false }) { $0.project! }
        var result = projects.keys.sorted(by: order).map { project in
            ContainerGroup(
                id: "\(context)/compose/\(project)", name: project, isCompose: true,
                containers: projects[project, default: []].sorted { order($0.name, $1.name) })
        }
        let standalone = containers.filter { $0.project?.isEmpty != false }.sorted { order($0.name, $1.name) }
        if !standalone.isEmpty {
            result.append(
                ContainerGroup(
                    id: "\(context)/standalone", name: "Standalone containers",
                    isCompose: false, containers: standalone))
        }
        return result
    }
    private static func order(_ lhs: String, _ rhs: String) -> Bool {
        let folded = lhs.localizedStandardCompare(rhs)
        return folded == .orderedSame ? lhs < rhs : folded == .orderedAscending
    }
}

public enum ContainerAction: String, Sendable, CaseIterable {
    case start, stop, restart
    public var label: String { rawValue.capitalized }
}

public struct OperationResult: Sendable, Equatable {
    public let containerID: String
    public let succeeded: Bool
    public let message: String
    public init(containerID: String, succeeded: Bool, message: String) {
        self.containerID = containerID
        self.succeeded = succeeded
        self.message = message
    }
}

public struct OperationReport: Sendable, Equatable {
    public let action: ContainerAction
    public let results: [OperationResult]
    public var succeeded: Bool { results.allSatisfy(\.succeeded) }
    public init(action: ContainerAction, results: [OperationResult]) {
        self.action = action
        self.results = results
    }
}

public struct ImageSummary: Identifiable, Sendable, Equatable {
    /// Distinguishes repository/tag rows that can refer to the same engine image.
    public let id: String
    /// The Docker Engine image identifier, suitable for copying into Docker commands.
    public let imageID: String
    public let repository: String
    public let tag: String
    public let size: String
    public let createdSince: String
    public var displayName: String { tag == "<none>" ? repository : "\(repository):\(tag)" }
    public init(
        id: String, repository: String, tag: String, size: String, createdSince: String = "", imageID: String? = nil
    ) {
        self.id = id
        self.imageID = imageID ?? id
        self.repository = repository
        self.tag = tag
        self.size = size
        self.createdSince = createdSince
    }
}

public struct VolumeSummary: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let driver: String
    public let mountpoint: String
    public init(id: String, name: String, driver: String, mountpoint: String = "") {
        self.id = id
        self.name = name
        self.driver = driver
        self.mountpoint = mountpoint
    }
}

public struct NetworkSummary: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let driver: String
    public let scope: String
    public init(id: String, name: String, driver: String, scope: String = "local") {
        self.id = id
        self.name = name
        self.driver = driver
        self.scope = scope
    }
}

public struct EngineInfo: Sendable, Equatable {
    public let serverVersion: String
    public let architecture: String
    public let operatingSystem: String
    public let cpus: Int
    public let memoryBytes: UInt64
    public init(serverVersion: String, architecture: String, operatingSystem: String, cpus: Int, memoryBytes: UInt64) {
        self.serverVersion = serverVersion
        self.architecture = architecture
        self.operatingSystem = operatingSystem
        self.cpus = cpus
        self.memoryBytes = memoryBytes
    }
}

public struct ContainerInspection: Sendable, Equatable {
    public let json: String
    public let environmentKeys: [String]
    public let mounts: [String]
    public init(json: String, environmentKeys: [String] = [], mounts: [String] = []) {
        self.json = json
        self.environmentKeys = environmentKeys
        self.mounts = mounts
    }
}

public enum DockerError: LocalizedError, Sendable, Equatable {
    case executableNotFound
    case invalidExecutable(String)
    case unknownContext(String)
    case remoteContextUnsupported(String)
    case invalidContainerID
    case invalidResponse(String)
    case commandFailed(String)
    case timedOut
    case outputLimitExceeded

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Docker CLI was not found. Install the Docker CLI or choose its executable in Settings."
        case .invalidExecutable(let path): "The selected Docker executable cannot be run: \(path)"
        case .unknownContext(let name): "Docker context ‘\(name)’ was not found."
        case .remoteContextUnsupported(let name):
            "‘\(name)’ is not a local Unix-socket context. Dockey currently supports local engines only."
        case .invalidContainerID: "The container identifier is invalid. Refresh the container list and try again."
        case .invalidResponse(let operation): "Docker returned an unreadable response for \(operation)."
        case .commandFailed(let message): message.isEmpty ? "Docker could not complete the operation." : message
        case .timedOut: "Docker did not respond in time. Check the engine and try again."
        case .outputLimitExceeded:
            "Docker output exceeded the safe display buffer. Reduce the log tail or refresh the view."
        }
    }
}
