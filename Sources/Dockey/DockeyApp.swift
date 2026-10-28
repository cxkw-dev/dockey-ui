import AppKit
import SwiftUI

struct LaunchOptions {
    let demo: Bool
    let appearance: String?
    let screenshotPath: String?
    let iconPath: String?

    init(arguments: [String] = CommandLine.arguments) {
        demo = arguments.contains("--demo")
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
        if options.screenshotPath != nil, !options.demo {
            fputs("Documentation screenshots require --demo. No live Docker data was captured.\n", stderr)
            NSApp.terminate(nil)
            return
        }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(1500))
                if let icon = DockeyIcon.render() { NSApp.applicationIconImage = icon }
                if let path = options.iconPath {
                    try DockeyIcon.write(to: URL(fileURLWithPath: path))
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
                if options.iconPath != nil || options.screenshotPath != nil { NSApp.terminate(nil) }
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
    static func render() -> NSImage? {
        let renderer = ImageRenderer(
            content:
                ZStack {
                    RoundedRectangle(cornerRadius: 220).fill(Color(red: 0.96, green: 0.96, blue: 0.97))
                    DockeyMascot().frame(width: 900, height: 900)
                }.frame(width: 1024, height: 1024)
        )
        renderer.scale = 1
        return renderer.nsImage
    }

    static func write(to destination: URL) throws {
        guard let image = render(), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }
}
