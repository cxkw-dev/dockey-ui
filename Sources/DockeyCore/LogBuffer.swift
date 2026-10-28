import Foundation

/// Keeps the newest valid UTF-8 suffix, bounded by bytes rather than grapheme count.
/// A single displayed Character can contain arbitrarily many combining Unicode scalars.
public struct LogBuffer: Sendable, Equatable {
    public let limitBytes: Int
    public private(set) var text = ""

    public init(limitBytes: Int = 1_048_576) {
        self.limitBytes = max(0, limitBytes)
    }

    public mutating func append(_ chunk: String) {
        guard limitBytes > 0 else { return }
        let incomingBytes = chunk.utf8.count
        if incomingBytes <= limitBytes - text.utf8.count {
            text.append(chunk)
        } else if incomingBytes >= limitBytes {
            text = Self.validSuffix(chunk, maxBytes: limitBytes)
        } else {
            text = Self.validSuffix(text, maxBytes: limitBytes - incomingBytes) + chunk
        }
    }

    public mutating func clear() {
        text.removeAll(keepingCapacity: false)
    }

    private static func validSuffix(_ value: String, maxBytes: Int) -> String {
        // A suffix may start inside a scalar. Skip its continuation bytes instead
        // of inserting replacement glyphs, which could themselves exceed the cap.
        let bytes = value.utf8.suffix(maxBytes).drop { (0x80...0xBF).contains($0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
