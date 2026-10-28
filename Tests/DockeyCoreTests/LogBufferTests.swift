import Foundation
import Testing

@testable import DockeyCore

@Suite("Bounded UTF-8 log buffer")
struct LogBufferTests {
    @Test func retainsNewestAsciiWithoutExceedingCapacity() {
        var buffer = LogBuffer(limitBytes: 8)
        buffer.append("hello")
        buffer.append(" world")
        #expect(buffer.text == "lo world")
        buffer.append("0123456789")
        #expect(buffer.text == "23456789")
        #expect(buffer.text.utf8.count == 8)
    }

    @Test func trimmingNeverSplitsAMultibyteScalar() {
        var buffer = LogBuffer(limitBytes: 4)
        buffer.append("ab🐳c")
        #expect(buffer.text == "c")
        buffer.append("é")
        #expect(buffer.text == "cé")
        #expect(buffer.text.utf8.count <= 4)
        #expect(!buffer.text.contains("\u{FFFD}"))
    }

    @Test func aHugeSingleGraphemeCannotDefeatTheByteLimit() {
        let hugeGrapheme = "e" + String(repeating: "\u{0301}", count: 100_000)
        #expect(hugeGrapheme.count == 1)
        var buffer = LogBuffer(limitBytes: 64)
        buffer.append(hugeGrapheme)
        #expect(buffer.text.utf8.count <= 64)
        #expect(!buffer.text.contains("\u{FFFD}"))
        buffer.append("last line\n")
        #expect(buffer.text.hasSuffix("last line\n"))
        #expect(buffer.text.utf8.count <= 64)
    }

    @Test func clearAndZeroCapacityArePredictable() {
        var buffer = LogBuffer(limitBytes: 3)
        buffer.append("abc")
        buffer.append("")
        #expect(buffer.text == "abc")
        buffer.clear()
        #expect(buffer.text.isEmpty)
        buffer.append("éé")
        #expect(buffer.text == "é")
        var zero = LogBuffer(limitBytes: -1)
        zero.append("anything")
        #expect(zero.limitBytes == 0)
        #expect(zero.text.isEmpty)
    }
}
