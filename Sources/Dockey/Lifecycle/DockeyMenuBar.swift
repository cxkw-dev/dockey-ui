import AppKit
import SwiftUI

struct DockeyStatusMenu: View {
    let lifecycle: MainWindowLifecycle
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Dockey") {
            guard !lifecycle.isTerminating else { return }
            if !lifecycle.show() { openWindow(id: "main") }
        }
        Divider()
        Button("Quit Dockey") { NSApp.terminate(nil) }
    }
}

@MainActor
enum DockeyMenuBarIcon {
    /// A tiny original template silhouette: crate, soft puff, and two clear eye cutouts.
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            let puff = NSBezierPath()
            puff.move(to: NSPoint(x: 3.1, y: 8.8))
            puff.curve(to: NSPoint(x: 4.2, y: 6), controlPoint1: NSPoint(x: 1.7, y: 6.4), controlPoint2: NSPoint(x: 2.5, y: 5.8))
            puff.curve(to: NSPoint(x: 7.2, y: 5.4), controlPoint1: NSPoint(x: 4.5, y: 4.5), controlPoint2: NSPoint(x: 6, y: 4.5))
            puff.curve(to: NSPoint(x: 10.8, y: 5.4), controlPoint1: NSPoint(x: 8, y: 4.4), controlPoint2: NSPoint(x: 10, y: 4.4))
            puff.curve(to: NSPoint(x: 13.8, y: 6), controlPoint1: NSPoint(x: 12, y: 4.5), controlPoint2: NSPoint(x: 13.5, y: 4.5))
            puff.curve(to: NSPoint(x: 14.9, y: 8.8), controlPoint1: NSPoint(x: 15.5, y: 5.8), controlPoint2: NSPoint(x: 16.3, y: 6.4))
            puff.curve(to: NSPoint(x: 14.1, y: 13.6), controlPoint1: NSPoint(x: 17.2, y: 10.9), controlPoint2: NSPoint(x: 16.2, y: 13.7))
            puff.curve(to: NSPoint(x: 11.6, y: 15.5), controlPoint1: NSPoint(x: 14.7, y: 15.5), controlPoint2: NSPoint(x: 12.9, y: 16.6))
            puff.curve(to: NSPoint(x: 6.4, y: 15.5), controlPoint1: NSPoint(x: 10.2, y: 17.1), controlPoint2: NSPoint(x: 7.8, y: 17.1))
            puff.curve(to: NSPoint(x: 3.9, y: 13.6), controlPoint1: NSPoint(x: 5.1, y: 16.6), controlPoint2: NSPoint(x: 3.3, y: 15.5))
            puff.curve(to: NSPoint(x: 3.1, y: 8.8), controlPoint1: NSPoint(x: 1.8, y: 13.7), controlPoint2: NSPoint(x: 0.8, y: 10.9))
            puff.close()
            puff.fill()
            NSBezierPath(roundedRect: NSRect(x: 5.2, y: 1, width: 7.6, height: 4.1), xRadius: 1, yRadius: 1).fill()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            for x in [6.6, 10.2] { NSBezierPath(ovalIn: NSRect(x: x - 1.35, y: 8.1, width: 2.7, height: 3.3)).fill() }
            for x in [7.4, 10.2] { NSBezierPath(rect: NSRect(x: x, y: 2, width: 0.65, height: 2)).fill() }
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.setFill()
            for x in [6.9, 10.5] { NSBezierPath(ovalIn: NSRect(x: x - 0.5, y: 9, width: 1, height: 1.8)).fill() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dockey"
        return image
    }()
}
