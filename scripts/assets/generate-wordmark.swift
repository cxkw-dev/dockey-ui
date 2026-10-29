#!/usr/bin/env swift
// Export the approved, editable Rounded 01 outline as native and portable vectors.
import CoreGraphics
import CryptoKit
import Foundation

if CommandLine.arguments.count != 1 {
    print("Usage: swift scripts/assets/generate-wordmark.swift\nRegenerates native and portable vectors from the approved Rounded 01 outline.")
    exit(CommandLine.arguments.dropFirst().elementsEqual(["--help"]) ? 0 : 1)
}

struct SourceManifest: Decodable {
    struct Asset: Decodable { let file: String; let sha256: String }
    let outline: Asset
}

final class OutlineDocument: NSObject, XMLParserDelegate {
    var paths: [String] = []
    var valid = true
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        switch name {
        case "svg", "title": break
        case "path":
            guard let data = attributes["d"], attributes["transform"] == nil else {
                valid = false
                return
            }
            paths.append(data)
        default: valid = false
        }
    }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
let directory = root.appendingPathComponent("design/wordmark")
let manifest = try JSONDecoder().decode(SourceManifest.self, from: Data(contentsOf: directory.appendingPathComponent("SOURCE.json")))
guard manifest.outline.file == "rounded-outline.svg" else { fatalError("Unexpected wordmark source.") }
let data = try Data(contentsOf: directory.appendingPathComponent(manifest.outline.file))
let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
guard data.count < 512_000, hash == manifest.outline.sha256 else {
    fatalError("The approved wordmark outline has changed; update its source record before exporting.")
}
let document = OutlineDocument()
let parser = XMLParser(data: data)
parser.shouldResolveExternalEntities = false
parser.delegate = document
guard parser.parse(), document.valid, !document.paths.isEmpty else {
    fatalError("Use an SVG containing absolute paths without transforms.")
}
let expression = try NSRegularExpression(pattern: #"[MLCQZ]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?"#)
let lettering = CGMutablePath()
for pathData in document.paths {
    let range = NSRange(location: 0, length: (pathData as NSString).length)
    let leftovers = expression.stringByReplacingMatches(in: pathData, range: range, withTemplate: "")
        .filter { !$0.isWhitespace && $0 != "," }
    guard leftovers.isEmpty else { fatalError("Unsupported SVG path syntax; use absolute M/L/Q/C/Z commands.") }
    let tokens = expression.matches(in: pathData, range: range).map { (pathData as NSString).substring(with: $0.range) }
    guard tokens.count < 20_000 else { fatalError("The wordmark outline is unexpectedly large.") }
    var cursor = 0
    func coordinates(_ count: Int) -> [CGFloat] {
        guard cursor + count <= tokens.count else { fatalError("Incomplete vector command.") }
        let values = tokens[cursor..<cursor + count].map { token -> CGFloat in
            guard let value = Double(token), value.isFinite, abs(value) <= 10_000 else {
                fatalError("Invalid vector coordinate.")
            }
            return CGFloat(value)
        }
        cursor += count
        return values
    }
    while cursor < tokens.count {
        let operation = tokens[cursor]
        cursor += 1
        switch operation {
        case "M":
            let p = coordinates(2); lettering.move(to: CGPoint(x: p[0], y: p[1]))
        case "L":
            let p = coordinates(2); lettering.addLine(to: CGPoint(x: p[0], y: p[1]))
        case "Q":
            let p = coordinates(4)
            lettering.addQuadCurve(to: CGPoint(x: p[2], y: p[3]), control: CGPoint(x: p[0], y: p[1]))
        case "C":
            let p = coordinates(6)
            lettering.addCurve(to: CGPoint(x: p[4], y: p[5]), control1: CGPoint(x: p[0], y: p[1]), control2: CGPoint(x: p[2], y: p[3]))
        case "Z": lettering.closeSubpath()
        default: fatalError("Unsupported vector command.")
        }
    }
}
let bounds = lettering.boundingBoxOfPath
guard bounds.width > 0, bounds.height > 0, bounds.width <= 4096, bounds.height <= 4096 else {
    fatalError("Invalid wordmark bounds.")
}
var normalization = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
let outline = lettering.copy(using: &normalization)!
// Estimate the filled outline's optical center offline, including its counters and swashes.
// The app uses only the exported constant; it performs no sampling at runtime.
let rows = 128
let columns = max(1, Int(CGFloat(rows) * bounds.width / bounds.height))
var filledSamples: CGFloat = 0
var weightedY: CGFloat = 0
for row in 0..<rows {
    let y = (CGFloat(row) + 0.5) / CGFloat(rows)
    for column in 0..<columns {
        let x = (CGFloat(column) + 0.5) / CGFloat(columns)
        if outline.contains(CGPoint(x: x * bounds.width, y: y * bounds.height)) {
            filledSamples += 1
            weightedY += y
        }
    }
}
guard filledSamples > 0 else { fatalError("The exported wordmark is empty.") }
let opticalCenterRatio = weightedY / filledSamples
func number(_ value: CGFloat) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value) }
func point(_ value: CGPoint) -> String { "CGPoint(x: \(number(value.x)), y: \(number(value.y)))" }
func pair(_ value: CGPoint) -> String { "\(number(value.x)) \(number(value.y))" }
var swiftCommands: [String] = []
var svgCommands: [String] = []
outline.applyWithBlock { pointer in
    let element = pointer.pointee
    switch element.type {
    case .moveToPoint:
        swiftCommands.append("path.move(to: \(point(element.points[0])))")
        svgCommands.append("M\(pair(element.points[0]))")
    case .addLineToPoint:
        swiftCommands.append("path.addLine(to: \(point(element.points[0])))")
        svgCommands.append("L\(pair(element.points[0]))")
    case .addQuadCurveToPoint:
        swiftCommands.append("path.addQuadCurve(to: \(point(element.points[1])), control: \(point(element.points[0])))")
        svgCommands.append("Q\(pair(element.points[0])) \(pair(element.points[1]))")
    case .addCurveToPoint:
        swiftCommands.append("path.addCurve(to: \(point(element.points[2])), control1: \(point(element.points[0])), control2: \(point(element.points[1])))")
        svgCommands.append("C\(pair(element.points[0])) \(pair(element.points[1])) \(pair(element.points[2]))")
    case .closeSubpath:
        swiftCommands.append("path.closeSubpath()")
        svgCommands.append("Z")
    @unknown default: fatalError("Unsupported vector element.")
    }
}
let swift = """
// Vector lettering generated by scripts/assets/generate-wordmark.swift. Do not edit coordinates by hand.
// Rounded 01 project artwork, Apache-2.0. See design/wordmark/SOURCE.json.
import SwiftUI

struct DockeyWordmarkShape: Shape {
    static let aspectRatio: CGFloat = \(number(bounds.width)) / \(number(bounds.height))
    static let opticalCenterRatio: CGFloat = \(number(opticalCenterRatio))
    private static let outline: Path = {
        var path = Path()
\(swiftCommands.map { "        " + $0 }.joined(separator: "\n"))
        return path
    }()

    func path(in rect: CGRect) -> Path {
        Self.outline.applying(CGAffineTransform(
            a: rect.width / \(number(bounds.width)), b: 0, c: 0,
            d: rect.height / \(number(bounds.height)), tx: rect.minX, ty: rect.minY))
    }
}

"""
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(number(bounds.width)) \(number(bounds.height))" role="img" aria-labelledby="title">
  <title id="title">Dockey</title>
  <!-- Rounded 01 project artwork. Editable source and provenance: wordmark/SOURCE.json. -->
  <path fill="currentColor" d="\(svgCommands.joined(separator: " "))"/>
</svg>

"""
try swift.write(to: root.appendingPathComponent("Sources/Dockey/Design/DockeyWordmarkShape.swift"), atomically: true, encoding: .utf8)
try svg.write(to: root.appendingPathComponent("design/dockey-wordmark.svg"), atomically: true, encoding: .utf8)
print("Exported Dockey wordmark: \(number(bounds.width)) × \(number(bounds.height)), \(swiftCommands.count) vector elements.")
