import AppKit
import Darwin
import SwiftUI

struct LaunchOptions {
    let demo: Bool
    let appearance: String?
    let screenshotPath: String?
    let section: AppSection?
    let iconPath: String?
    let verifyResources: Bool
    let iconDarkPreview: Bool

    var showsMenuBarItem: Bool { !verifyResources && screenshotPath == nil && iconPath == nil }

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
        section = value(after: "--section").flatMap(AppSection.init(rawValue:))
        iconPath = value(after: "--render-icon")
    }
}

@main
@MainActor
struct DockeyApp: App {
    @NSApplicationDelegateAdaptor(DockeyAppDelegate.self) private var appDelegate
    @StateObject private var store: AppStore
    private let launchOptions: LaunchOptions

    init() {
        let options = LaunchOptions()
        launchOptions = options
        if options.screenshotPath != nil, !options.demo {
            fputs("Documentation screenshots require --demo. No live Docker data was captured.\n", stderr)
            exit(EXIT_FAILURE)
        }
        if options.verifyResources {
            do {
                try DockeyFonts.verifyBundledFonts()
                print("Dockey bundled fonts verified.")
            } catch {
                fputs("Dockey bundled font verification failed.\n", stderr)
                exit(EXIT_FAILURE)
            }
            do {
                try ServiceIconResources.verifyBundledAssets()
                print("Dockey bundled service icons verified.")
            } catch {
                fputs("Dockey bundled service icon verification failed.\n", stderr)
                exit(EXIT_FAILURE)
            }
            if options.screenshotPath == nil, options.iconPath == nil { exit(EXIT_SUCCESS) }
        }
        if let path = options.iconPath {
            do {
                try DockeyIcon.write(to: URL(fileURLWithPath: path), darkPreview: options.iconDarkPreview)
                exit(EXIT_SUCCESS)
            } catch {
                fputs("Dockey could not render the requested icon.\n", stderr)
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
        Window("Dockey", id: "main") {
            RootView(store: store)
                .onAppear { appDelegate.bindStore(store) }
                .background(WindowBridge(lifecycle: appDelegate.mainWindow))
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
            SettingsView(store: store)
                .preferredColorScheme(colorScheme)
        }
        MenuBarExtra(isInserted: .constant(launchOptions.showsMenuBarItem)) {
            StatusMenu(lifecycle: appDelegate.mainWindow)
        } label: {
            Image(nsImage: MenuBarIcon.image).renderingMode(.template)
                .accessibilityLabel("Dockey")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class DockeyAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    let mainWindow = MainWindowLifecycle()

    func bindStore(_ store: AppStore) {
        self.store = store
        mainWindow.visibilityChanged = { [weak store] visible in store?.setMainWindowVisible(visible) }
        mainWindow.updateVisibility(applicationHidden: NSApp.isHidden)
        store.setApplicationActive(NSApp.isActive)
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindow.prepareForTermination()
        store?.shutdown()
    }

    func applicationDidBecomeActive(_ notification: Notification) { store?.setApplicationActive(true) }
    func applicationDidResignActive(_ notification: Notification) { store?.setApplicationActive(false) }
    func applicationDidHide(_ notification: Notification) { mainWindow.updateVisibility(applicationHidden: true) }
    func applicationDidUnhide(_ notification: Notification) { mainWindow.updateVisibility() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Return false after showing the existing window, suppressing AppKit's untitled-window fallback.
        guard !mainWindow.isTerminating else { return false }
        return !mainWindow.show()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let options = LaunchOptions()
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        {
            NSApp.applicationIconImage = icon
        }
        guard let path = options.screenshotPath else { return }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(1500))
                if let section = options.section, let store = self.store {
                    store.selectSection(section)
                    try await Task.sleep(for: .milliseconds(300))
                }
                guard let window = NSApp.windows.first(where: { $0.title == "Dockey" && $0.isVisible }) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                // Documentation exports use a consistent canvas, independent of saved live-window size.
                window.setContentSize(NSSize(width: 1280, height: 960))
                try AppScreenshot.capture(window: window, destination: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            } catch {
                fputs(
                    "Dockey could not export the requested development artifact: \(error.localizedDescription)\n",
                    stderr)
                exit(EXIT_FAILURE)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
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
