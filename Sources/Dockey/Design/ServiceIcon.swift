import AppKit
import DockeyCore
import SwiftUI

/// Reviewed vendor marks and the ISC-licensed elephant use cached native vector PDFs.
/// Source artwork and provenance live in design/services/.
@MainActor
struct ServiceIcon: View {
    let identity: ServiceIdentity
    var size: CGFloat = 24
    @Environment(\.colorScheme) private var scheme

    private var colors: ServiceIconColors { ServiceIconColors(dark: scheme == .dark) }
    // Balance visible weight: dense solid bars need less space than open outlines or a narrow leaf.
    private var opticalSize: CGFloat {
        switch identity {
        case .clickhouse: size * 18 / 24
        case .langfuse, .temporal, .postgresql: size * 22 / 24
        case .aiFocus: size * 18 / 24
        case .mongodb: size * 23 / 24
        default: size
        }
    }

    var body: some View {
        let colors = colors
        Group {
            if let image = ServiceIconResources.image(for: identity, dark: scheme == .dark) {
                Image(nsImage: image).resizable().renderingMode(.original).scaledToFit()
                    .frame(width: opticalSize, height: opticalSize)
                    .offset(x: identity == .aiFocus ? size / 48 : 0)
            } else {
                Canvas { context, canvasSize in
                    var context = context
                    let scale = min(canvasSize.width, canvasSize.height) / 24
                    context.scaleBy(x: scale, y: scale)
                    switch identity {
                    case .redis: cache(context, colors: colors)
                    default: container(context, colors: colors)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .help(identity == .generic ? "Container image" : "\(identity.displayName) image")
        .accessibilityHidden(true)
    }

    private func cache(_ context: GraphicsContext, colors: ServiceIconColors) {
        // Three front-facing cache lines, rather than a vendor's stacked diamond mark.
        for y in [4.1, 10, 15.9] {
            let line = Path(roundedRect: CGRect(x: 3.5, y: y, width: 17, height: 4), cornerRadius: 1.3)
            context.fill(line, with: .color(colors.accent.opacity(0.12)))
            context.stroke(line, with: .color(colors.accent), lineWidth: 1.25)
            context.fill(
                Path(ellipseIn: CGRect(x: 6, y: y + 1.3, width: 1.4, height: 1.4)),
                with: .color(colors.accent))
            var contents = Path()
            contents.move(to: CGPoint(x: 10, y: y + 2))
            contents.addLine(to: CGPoint(x: 17.3, y: y + 2))
            context.stroke(contents, with: .color(colors.accent), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }
    }

    private func container(_ context: GraphicsContext, colors: ServiceIconColors) {
        var cube = Path()
        cube.move(to: CGPoint(x: 12, y: 3.5))
        cube.addLine(to: CGPoint(x: 20, y: 8))
        cube.addLine(to: CGPoint(x: 20, y: 16.5))
        cube.addLine(to: CGPoint(x: 12, y: 21))
        cube.addLine(to: CGPoint(x: 4, y: 16.5))
        cube.addLine(to: CGPoint(x: 4, y: 8))
        cube.closeSubpath()
        cube.move(to: CGPoint(x: 4, y: 8))
        cube.addLine(to: CGPoint(x: 12, y: 12.5))
        cube.addLine(to: CGPoint(x: 20, y: 8))
        cube.move(to: CGPoint(x: 12, y: 12.5))
        cube.addLine(to: CGPoint(x: 12, y: 21))
        cube.move(to: CGPoint(x: 8, y: 5.75))
        cube.addLine(to: CGPoint(x: 16, y: 10.25))
        context.stroke(
            cube, with: .color(colors.accent),
            style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
    }
}

private struct ServiceIconColors {
    let dark: Bool
    var accent: Color { Color(hex: dark ? 0xB8B8B8 : 0x626262) }
}

/// AppKit's PDF representation preserves vectors on every supported macOS version.
/// Each theme asset is decoded once; list updates never re-read or re-parse artwork.
@MainActor
enum ServiceIconResources {
    private static let bundledNames = ["clickhouse", "langfuse", "temporal", "mongodb", "postgresql", "ai-focus"]
    private static let licenses = [
        "ClickHouse-Apache-2.0.txt", "Langfuse-MIT.txt", "Temporal-MIT.txt", "MongoDB-LeafyGreen-Apache-2.0.txt",
        "Lucide-Lab-ISC.txt",
    ]
    private static var images: [String: NSImage] = [:]
    private static var failedNames: Set<String> = []
    private static let resources: URL? = {
        let bundleURL: URL
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let directory = Bundle.main.resourceURL else { return nil }
            bundleURL = directory.appendingPathComponent("Dockey_Dockey.bundle")
        } else {
            bundleURL = Bundle.module.bundleURL
        }
        return ["Contents/Resources/Resources", "Resources"]
            .map { bundleURL.appendingPathComponent($0, isDirectory: true) }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("ServiceIcons").path) }
    }()

    static func image(for identity: ServiceIdentity, dark: Bool) -> NSImage? {
        guard bundledNames.contains(identity.rawValue) else { return nil }
        return image(named: "\(identity.rawValue)-\(dark ? "dark" : "light")")
    }

    private static func image(named name: String) -> NSImage? {
        if let image = images[name] { return image }
        guard !failedNames.contains(name) else { return nil }
        guard let directory = resources?.appendingPathComponent("ServiceIcons"),
            let image = NSImage(contentsOf: directory.appendingPathComponent("\(name).pdf")), image.isValid,
            image.size.width > 0, image.size.height > 0
        else {
            failedNames.insert(name)
            return nil
        }
        image.isTemplate = false
        images[name] = image
        return image
    }

    static func verifyBundledAssets() throws {
        guard Bundle.main.bundleURL.pathExtension == "app", let resources else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        for service in bundledNames {
            for theme in ["dark", "light"] {
                let name = "\(service)-\(theme)"
                let directory = resources.appendingPathComponent("ServiceIcons")
                guard let svg = try? Data(contentsOf: directory.appendingPathComponent("\(name).svg")), !svg.isEmpty,
                    let pdf = try? Data(contentsOf: directory.appendingPathComponent("\(name).pdf")),
                    pdf.starts(with: Data("%PDF-".utf8)), let image = image(named: name), rasterizes(image)
                else { throw CocoaError(.fileReadCorruptFile) }
            }
        }
        for license in licenses {
            let url = resources.appendingPathComponent("ServiceIconLicenses/\(license)")
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
        }
    }

    private static func rasterizes(_ image: NSImage) -> Bool {
        var rect = CGRect(x: 0, y: 0, width: 96, height: 96)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return false }
        var pixels = [UInt8](repeating: 0, count: 96 * 96 * 4)
        let drew = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 96, height: 96, bitsPerComponent: 8,
                bytesPerRow: 96 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(cgImage, in: rect)
            return true
        }
        return drew && stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
    }
}
