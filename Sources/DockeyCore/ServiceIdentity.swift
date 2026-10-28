import Foundation

/// A presentation hint from a known image repository, not proof of image provenance or signatures.
/// Container names, Compose service names, and arbitrary registry mirrors do not establish identity.
public enum ServiceIdentity: String, Sendable, CaseIterable, Identifiable {
    case clickhouse, mongodb, redis, postgresql, generic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .clickhouse: "ClickHouse"
        case .mongodb: "MongoDB"
        case .redis: "Redis"
        case .postgresql: "PostgreSQL"
        case .generic: "Container"
        }
    }

    public init(imageReference: String) {
        guard let repository = Self.dockerHubRepository(imageReference) else {
            self = .generic
            return
        }
        switch repository {
        case "clickhouse/clickhouse-server": self = .clickhouse
        case "mongodb/mongodb-community-server", "mongodb/mongodb-enterprise-server", "mongodb/mongodb-atlas-local":
            self = .mongodb
        case "redis/redis-stack", "redis/redis-stack-server": self = .redis
        default:
            let components = repository.split(separator: "/")
            if components.count == 1 {
                self = Self.officialImage(String(components[0]))
            } else if components.count == 2,
                components[0] == "library" || Self.officialArchitectureNamespaces.contains(String(components[0]))
            {
                self = Self.officialImage(String(components[1]))
            } else {
                self = .generic
            }
        }
    }

    private static func officialImage(_ name: String) -> Self {
        switch name {
        case "clickhouse": .clickhouse
        case "mongo": .mongodb
        case "redis": .redis
        case "postgres": .postgresql
        default: .generic
        }
    }

    // Docker Official Images architecture namespaces, not arbitrary prefixes to strip.
    private static let officialArchitectureNamespaces: Set<String> = [
        "amd64", "arm32v5", "arm32v6", "arm32v7", "arm64v8", "i386", "ppc64le", "riscv64", "s390x",
    ]

    private static func dockerHubRepository(_ reference: String) -> String? {
        guard reference.utf8.count <= 4_096 else { return nil }
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let digestParts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard (1...2).contains(digestParts.count), !digestParts[0].isEmpty else { return nil }
        if digestParts.count == 2, !isValidDigest(digestParts[1]) { return nil }
        var components = digestParts[0].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.contains(where: \.isEmpty), var leaf = components.popLast() else { return nil }
        // Only the final path component can contain a tag; a registry port must retain its ownership.
        if let separator = leaf.firstIndex(of: ":") {
            guard isValidTag(leaf[leaf.index(after: separator)...]) else { return nil }
            leaf = String(leaf[..<separator])
        }
        guard !leaf.isEmpty else { return nil }
        components.append(leaf)
        if components.count > 1, let first = components.first,
            first.contains(".") || first.contains(":") || first == "localhost"
        {
            // These are Docker Hub registry hostnames. Ports and other registries remain generic.
            guard ["docker.io", "index.docker.io", "registry-1.docker.io"].contains(first.lowercased()) else {
                return nil
            }
            components.removeFirst()
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }

    private static func isValidTag(_ tag: Substring) -> Bool {
        let bytes = tag.utf8
        guard (1...128).contains(bytes.count), let first = bytes.first,
            isASCIIAlphanumeric(first) || first == 95
        else { return false }
        return bytes.allSatisfy { isASCIIAlphanumeric($0) || $0 == 95 || $0 == 46 || $0 == 45 }
    }

    private static func isValidDigest(_ digest: Substring) -> Bool {
        let parts = digest.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let length: Int
        switch parts[0] {
        case "sha256": length = 64
        case "sha384": length = 96
        case "sha512": length = 128
        default: return false
        }
        return parts[1].utf8.count == length
            && parts[1].utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }
}
