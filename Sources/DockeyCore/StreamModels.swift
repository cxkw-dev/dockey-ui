import Foundation

/// Minimal lifecycle metadata. Actor attributes and other event payloads are never retained.
public struct DockerEvent: Sendable, Equatable {
    public let type: String
    public let action: String
    public let actorID: String
    public let timestamp: Date?
    public var id: String { actorID }

    public init(type: String, action: String, actorID: String, timestamp: Date? = nil) {
        self.type = type
        self.action = action
        self.actorID = actorID
        self.timestamp = timestamp
    }

    public init(type: String, action: String, id: String, timestamp: Date? = nil) {
        self.init(type: type, action: action, actorID: id, timestamp: timestamp)
    }
}

/// A bounded JSON-lines framer that preserves partial records and ANSI sequences across chunks.
/// Docker stats may emit terminal clear/cursor sequences even when its JSON format is selected.
struct DockerStreamFramer: Sendable {
    private enum EscapeState: Sendable { case none, escape, csi, osc, oscEscape }
    private var escapeState = EscapeState.none
    private var pending = Data()
    private let limit = 65_536

    mutating func append(_ chunk: String) throws -> [String] {
        var lines: [String] = []
        for byte in chunk.utf8 {
            switch escapeState {
            case .escape:
                if byte == 91 {
                    escapeState = .csi
                } else if byte == 93 {
                    escapeState = .osc
                } else {
                    escapeState = .none
                }
                continue
            case .csi:
                if (64...126).contains(byte) { escapeState = .none }
                continue
            case .osc:
                if byte == 7 { escapeState = .none } else if byte == 27 { escapeState = .oscEscape }
                continue
            case .oscEscape:
                if byte == 92 { escapeState = .none } else { escapeState = byte == 27 ? .oscEscape : .osc }
                continue
            case .none: break
            }
            if byte == 27 {
                escapeState = .escape
            } else if byte == 10 || byte == 13 {
                if let line = try takeLine() { lines.append(line) }
            } else {
                guard pending.count < limit else { throw DockerError.outputLimitExceeded }
                pending.append(byte)
            }
        }
        return lines
    }

    mutating func finish() throws -> [String] {
        if let line = try takeLine() { return [line] }
        return []
    }

    private mutating func takeLine() throws -> String? {
        guard let line = String(data: pending, encoding: .utf8) else {
            throw DockerError.invalidResponse("stream encoding")
        }
        pending.removeAll(keepingCapacity: true)
        let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
