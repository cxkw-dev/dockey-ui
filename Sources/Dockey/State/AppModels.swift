import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case containers, images, volumes, networks, activity
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .containers: "shippingbox"
        case .images: "square.stack.3d.up"
        case .volumes: "externaldrive"
        case .networks: "network"
        case .activity: "waveform.path.ecg"
        }
    }
}

enum ContainerFilter: String, CaseIterable, Identifiable {
    case all, running, stopped, unhealthy
    var id: String { rawValue }
    var label: String { self == .all ? "All states" : rawValue.capitalized }
}

enum DetailTab: String, CaseIterable, Identifiable {
    case logs, inspect, stats, mounts
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let isError: Bool
}

struct AppPreferences: Codable, Equatable {
    var appearance = "system"
    var density = "compact"
    var showStopped = true
    var refreshInterval: Double = 5
    var stopTimeout = 10
    var logTail = 1000
    var logFontSize: Double = 12
    var logTimestamps = true
    var logWrap = false
    var dockerExecutable = ""
    var confirmStop = true

    mutating func normalize() {
        if !["system", "light", "dark"].contains(appearance) { appearance = "system" }
        if !["compact", "comfortable"].contains(density) { density = "compact" }
        refreshInterval = refreshInterval.isFinite ? min(max(refreshInterval, 2), 60) : 5
        stopTimeout = min(max(stopTimeout, 1), 120)
        logTail = min(max(logTail, 100), 10_000)
        logFontSize = logFontSize.isFinite ? min(max(logFontSize, 10), 22) : 12
        dockerExecutable = dockerExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
