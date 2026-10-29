import Foundation

/// Groups of engine data that could be reclaimed. Dockey only reports them; it never removes anything.
public enum CleanupKind: String, Sendable, CaseIterable, Identifiable {
    case danglingImage, unusedImage, stoppedContainer, anonymousVolume, namedVolume, buildCache
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .danglingImage: "Dangling images"
        case .unusedImage: "Unused images"
        case .stoppedContainer: "Stopped containers"
        case .anonymousVolume: "Unused anonymous volumes"
        case .namedVolume: "Unused named volumes"
        case .buildCache: "Build cache"
        }
    }

    public var explanation: String {
        switch self {
        case .danglingImage: "Untagged layers left behind by rebuilds and pulls. Nothing refers to them."
        case .unusedImage: "Tagged images with no container. They can be pulled or rebuilt again when needed."
        case .stoppedContainer:
            "Writable layers of containers that are not running. Removing a container discards files written inside it."
        case .anonymousVolume: "Unnamed volumes no container is attached to, usually left by removed containers."
        case .namedVolume:
            "Named volumes no container is attached to. These often hold database or application data; review each one."
        case .buildCache: "BuildKit cache not used by a running build. Later builds are slower until it warms again."
        }
    }

    /// Kinds whose removal can lose data the user cares about.
    public var needsReview: Bool { self == .namedVolume || self == .stoppedContainer }

    /// The Docker CLI arguments for removing every item of this kind, or nil when there is no safe bulk form.
    /// Named volumes intentionally have none: `volume prune --all` would remove data without per-volume review.
    public var bulkArguments: [String]? {
        switch self {
        case .danglingImage: ["image", "prune"]
        case .unusedImage: ["image", "prune", "--all"]
        case .stoppedContainer: ["container", "prune"]
        case .anonymousVolume: ["volume", "prune"]
        case .namedVolume: nil
        case .buildCache: ["builder", "prune", "--all"]
        }
    }
}

public struct CleanupCandidate: Identifiable, Sendable, Equatable {
    public var id: String { "\(kind.rawValue)/\(identifier)" }
    public let kind: CleanupKind
    /// Image ID, container ID, volume name, or build cache record ID.
    public let identifier: String
    public let name: String
    public let detail: String
    /// Nil when the engine did not report a size.
    public let bytes: UInt64?
    public let project: String?
    /// Arguments for removing this one item, or nil when Docker has no per-item form.
    public let removalArguments: [String]?

    public init(
        kind: CleanupKind, identifier: String, name: String, detail: String = "", bytes: UInt64?,
        project: String? = nil, removalArguments: [String]? = nil
    ) {
        self.kind = kind
        self.identifier = identifier
        self.name = name
        self.detail = detail
        self.bytes = bytes
        self.project = project
        self.removalArguments = removalArguments
    }
}

public struct StorageUsage: Identifiable, Sendable, Equatable {
    public enum Category: String, Sendable, CaseIterable {
        case images, containers, volumes, buildCache
        public var label: String {
            switch self {
            case .images: "Images"
            case .containers: "Containers"
            case .volumes: "Volumes"
            case .buildCache: "Build cache"
            }
        }
    }
    public var id: String { category.rawValue }
    public let category: Category
    public let count: Int
    public let activeCount: Int
    /// Sum of reported sizes, or nil for images: shared layers make per-image sizes overstate disk use.
    public let bytes: UInt64?
    public init(category: Category, count: Int, activeCount: Int, bytes: UInt64?) {
        self.category = category
        self.count = count
        self.activeCount = activeCount
        self.bytes = bytes
    }
}

public struct StorageReport: Sendable, Equatable {
    public let usage: [StorageUsage]
    public let candidates: [CleanupCandidate]

    public init(usage: [StorageUsage], candidates: [CleanupCandidate]) {
        self.usage = usage
        self.candidates = candidates
    }

    public func candidates(_ kind: CleanupKind) -> [CleanupCandidate] { candidates.filter { $0.kind == kind } }

    public func reclaimableBytes(_ kind: CleanupKind) -> UInt64 {
        candidates(kind).reduce(0) { $0 &+ ($1.bytes ?? 0) }
    }

    /// Lower bound: image figures use unique layer sizes, and `image prune --all` also covers dangling images.
    public var reclaimableBytes: UInt64 { CleanupKind.allCases.reduce(0) { $0 &+ reclaimableBytes($1) } }

    /// Space reclaimable without removing named volumes or containers' writable layers.
    public var lowRiskReclaimableBytes: UInt64 {
        CleanupKind.allCases.filter { !$0.needsReview }.reduce(0) { $0 &+ reclaimableBytes($1) }
    }
}

public enum CleanupCommand {
    /// A copyable command pinned to an explicit context. Dockey displays it and never runs it.
    public static func render(_ arguments: [String], context: String) -> String {
        (["docker", "--context", context] + arguments).map(quote).joined(separator: " ")
    }

    static func quote(_ value: String) -> String {
        let plain = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.,/:@%+=")
        if !value.isEmpty, value.unicodeScalars.allSatisfy(plain.contains) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

public enum ByteSize {
    /// Parses Docker's human sizes, such as `1.167GB`, `16.4kB (virtual 256MB)`, `0B`, or `12 MiB`.
    public static func parse(_ text: String) -> UInt64? {
        let token =
            text.trimmingCharacters(in: .whitespaces).split(separator: "(").first?
            .replacingOccurrences(of: " ", with: "") ?? ""
        guard let split = token.firstIndex(where: { $0.isLetter }),
            let value = Double(token[..<split]), value.isFinite, value >= 0
        else { return nil }
        let units: [String: Double] = [
            "b": 1, "kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12, "pb": 1e15,
            "kib": 1_024, "mib": 1_048_576, "gib": 1_073_741_824, "tib": 1_099_511_627_776,
        ]
        guard let scale = units[token[split...].lowercased()] else { return nil }
        let bytes = value * scale
        return bytes < Double(UInt64.max) ? UInt64(bytes.rounded()) : nil
    }

    public static func format(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }
}
