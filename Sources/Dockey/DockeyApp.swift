import AppKit
import Darwin
import SwiftUI

struct LaunchOptions {
    let demo: Bool
    let appearance: String?
    let screenshotPath: String?
    let iconPath: String?
    let verifyResources: Bool
    let iconDarkPreview: Bool

    init(arguments: [String] = CommandLine.arguments) {
        verifyResources = arguments.contains("--verify-resources")
        iconDarkPreview = arguments.contains("--icon-dark-preview")
        demo = arguments.contains("--demo") || verifyResources || arguments.contains("--render-icon")
        func value(after key: String) -> String? {
            guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        appearance = value(after: "--appearance")
        screenshotPath = value(after: "--screenshot")
        iconPath = value(after: "--render-icon")
    }
}

@main
@MainActor
struct DockeyApp: App {
    @NSApplicationDelegateAdaptor(DockeyAppDelegate.self) private var appDelegate
    @StateObject private var store: AppStore

    init() {
        let options = LaunchOptions()
        if options.screenshotPath != nil, !options.demo {
            fputs("Documentation screenshots require --demo. No live Docker data was captured.\n", stderr)
            exit(EXIT_FAILURE)
        }
        if options.verifyResources {
            do {
                try DockeyFonts.verifyBundledFonts()
                print("Dockey bundled fonts verified.")
                if options.screenshotPath == nil { exit(EXIT_SUCCESS) }
            } catch {
                fputs("Dockey bundled font verification failed.\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        _store = StateObject(wrappedValue: AppStore(demo: options.demo, appearance: options.appearance))
    }

    private var colorScheme: ColorScheme? {
        switch store.preferences.appearance {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup("Dockey", id: "main") {
            RootView(store: store)
                .onAppear { appDelegate.store = store }
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Refresh") { Task { await store.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("All Containers") { store.selectSection(.containers) }
                    .keyboardShortcut("1", modifiers: .command)
            }
        }
        Settings {
            DockeySettingsView(store: store)
                .preferredColorScheme(colorScheme)
        }
    }
}

@MainActor
final class DockeyAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?

    func applicationWillTerminate(_ notification: Notification) { store?.shutdown() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let options = LaunchOptions()
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(1500))
                if let icon = DockeyIcon.render() { NSApp.applicationIconImage = icon }
                if let path = options.iconPath {
                    try DockeyIcon.write(to: URL(fileURLWithPath: path), darkPreview: options.iconDarkPreview)
                    NSApp.terminate(nil)
                } else if let path = options.screenshotPath {
                    guard let window = NSApp.windows.first(where: { $0.title == "Dockey" && $0.isVisible }) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try AppScreenshot.capture(window: window, destination: URL(fileURLWithPath: path))
                    NSApp.terminate(nil)
                }
            } catch {
                fputs(
                    "Dockey could not export the requested development artifact: \(error.localizedDescription)\n",
                    stderr)
                if options.iconPath != nil || options.screenshotPath != nil { exit(EXIT_FAILURE) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
enum AppScreenshot {
    static func capture(window: NSWindow, destination: URL) throws {
        guard let content = window.contentView else { throw CocoaError(.fileWriteUnknown) }
        let view = content.superview ?? content
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }
}

@MainActor
enum DockeyIcon {
    static func render(darkPreview: Bool = false) -> NSImage? {
        let renderer = ImageRenderer(
            content:
                DockeyMascot()
                .frame(width: 860, height: 860)
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
        context.setShadow(
            offset: .zero, blur: 42, color: CGColor(srgbRed: 0.39, green: 0.82, blue: 0.84, alpha: 0.42))
        context.draw(mascot, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
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
