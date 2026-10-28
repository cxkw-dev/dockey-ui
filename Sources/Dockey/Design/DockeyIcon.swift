import AppKit
import SwiftUI

@MainActor
enum DockeyIcon {
    static func render(darkPreview: Bool = false) -> NSImage? {
        let renderer = ImageRenderer(
            content:
                DockeyMascot(treatment: .dock)
                .frame(width: 1100, height: 1100)
                .frame(width: 1024, height: 1024)
        )
        renderer.scale = 1
        guard let mascot = renderer.cgImage,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if darkPreview {
            context.setFillColor(CGColor(srgbRed: 0.063, green: 0.075, blue: 0.09, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
        let tile = CGPath(
            roundedRect: CGRect(x: 32, y: 32, width: 960, height: 960),
            cornerWidth: 218, cornerHeight: 218, transform: nil)
        context.addPath(tile)
        context.setFillColor(CGColor(srgbRed: 0.085, green: 0.105, blue: 0.14, alpha: 1))
        context.fillPath()
        context.saveGState()
        context.addPath(tile)
        context.clip()
        // Two static halo layers preserve the silhouette at small Dock sizes.
        // Rendering happens only when generating assets, never on a timer or during normal startup.
        context.setShadow(
            offset: .zero, blur: 90, color: CGColor(srgbRed: 0.40, green: 0.84, blue: 0.88, alpha: 0.68))
        context.draw(mascot, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        context.setShadow(
            offset: .zero, blur: 24, color: CGColor(srgbRed: 0.72, green: 0.98, blue: 0.97, alpha: 0.80))
        context.draw(mascot, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        context.restoreGState()
        context.addPath(tile)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07))
        context.setLineWidth(2)
        context.strokePath()
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 1024, height: 1024))
    }

    static func write(to destination: URL, darkPreview: Bool = false) throws {
        guard let image = render(darkPreview: darkPreview), let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }
}
