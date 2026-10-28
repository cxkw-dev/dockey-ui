import AppKit
import DockeyCore
import Foundation
import Testing

@testable import Dockey

@Suite("Persistent application lifecycle")
@MainActor
struct WindowLifecycleTests {
    @Test
    func hideAndRepeatedShowReuseTheSameWindow() {
        var activations = 0
        var visibleStates: [Bool] = []
        let lifecycle = MainWindowLifecycle { activations += 1 }
        let window = LifecycleWindowFixture()
        lifecycle.visibilityChanged = { visibleStates.append($0) }
        lifecycle.attach(window)
        lifecycle.hide()
        #expect(!window.isVisible)
        #expect(window.hideCount == 1)
        #expect(lifecycle.window === window)
        #expect(visibleStates.last == false)
        #expect(lifecycle.show())
        #expect(lifecycle.show())
        #expect(window.isVisible)
        #expect(window.showCount == 2)
        #expect(activations == 2)
        #expect(lifecycle.window === window, "Dock and menu Show must reuse the captured main window.")
        #expect(visibleStates.last == true)
    }

    @Test
    func miniaturizedAndHiddenApplicationWindowsPauseVisibilityAndShowRestoresThem() {
        let lifecycle = MainWindowLifecycle(activate: {})
        let window = LifecycleWindowFixture()
        var visible = true
        lifecycle.visibilityChanged = { visible = $0 }
        lifecycle.attach(window)
        window.isMiniaturized = true
        lifecycle.updateVisibility()
        #expect(!visible)
        #expect(lifecycle.show())
        #expect(!window.isMiniaturized)
        #expect(visible)
        lifecycle.updateVisibility(applicationHidden: true)
        #expect(!visible)
        lifecycle.updateVisibility(applicationHidden: false)
        #expect(visible)
    }

    @Test
    func lifecycleAndProxyDoNotOwnTheirWindowOrOriginalDelegate() {
        let lifecycle = MainWindowLifecycle(activate: {})
        var window: LifecycleWindowFixture? = LifecycleWindowFixture()
        lifecycle.attach(window!)
        weak var weakWindow = window
        window = nil
        #expect(weakWindow == nil)
        #expect(!lifecycle.show())

        var original: LifecycleDelegateFixture? = LifecycleDelegateFixture()
        let proxy = DockeyWindowDelegateProxy(original: original, hide: { _ in })
        weak var weakDelegate = original
        original = nil
        #expect(weakDelegate == nil)
        #expect(proxy.originalDelegate == nil)
    }

    @Test
    func optionalWindowDelegateCallbacksContinueToTheOriginalDelegate() {
        let original = LifecycleDelegateFixture()
        let proxy = DockeyWindowDelegateProxy(original: original, hide: { _ in })
        let delegate: any NSWindowDelegate = proxy
        let selector = #selector(NSWindowDelegate.windowDidResize(_:))
        #expect(proxy.responds(to: selector))
        #expect((proxy.forwardingTarget(for: selector) as? LifecycleDelegateFixture) === original)
        delegate.windowDidResize?(Notification(name: NSWindow.didResizeNotification))
        #expect(original.resizeCount == 1)
    }

    @Test
    func explicitTerminationStopsOwnedCommandsAndRefusesWindowReopen() throws {
        let domain = "dev.dockey.lifecycle-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let runner = LifecycleCommandFixture()
        let client = DockerClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"), runner: runner)
        let store = AppStore(defaults: defaults, client: client)
        let delegate = DockeyAppDelegate()
        delegate.store = store
        let window = LifecycleWindowFixture()
        delegate.mainWindow.attach(window)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(runner.cancelCount == 1)
        #expect(runner.runCount == 0, "Quitting cancels owned CLI work; it must never send engine mutations.")
        #expect(delegate.mainWindow.isTerminating)
        #expect(!delegate.mainWindow.show())
        #expect(window.showCount == 0)
    }

    @Test
    func interactiveDemoKeepsMenuBarWhileArtifactModesOmitIt() {
        #expect(LaunchOptions(arguments: ["Dockey"]).showsMenuBarItem)
        #expect(LaunchOptions(arguments: ["Dockey", "--demo"]).showsMenuBarItem)
        #expect(!LaunchOptions(arguments: ["Dockey", "--demo", "--screenshot", "/tmp/test.png"]).showsMenuBarItem)
        #expect(!LaunchOptions(arguments: ["Dockey", "--verify-resources"]).showsMenuBarItem)
        #expect(!LaunchOptions(arguments: ["Dockey", "--render-icon", "/tmp/test.png"]).showsMenuBarItem)
    }
}

@MainActor
private final class LifecycleWindowFixture: DockeyMainWindow {
    var isVisible = true
    var isMiniaturized = false
    var hideCount = 0
    var showCount = 0
    func hideDockeyWindow() { hideCount += 1; isVisible = false }
    func showDockeyWindow() { showCount += 1; isVisible = true; isMiniaturized = false }
}

@MainActor
private final class LifecycleDelegateFixture: NSObject, NSWindowDelegate {
    var resizeCount = 0
    func windowDidResize(_ notification: Notification) { resizeCount += 1 }
}

private final class LifecycleCommandFixture: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var cancellations = 0
    private var requests = 0
    var cancelCount: Int { lock.withLock { cancellations } }
    var runCount: Int { lock.withLock { requests } }
    func cancelAll() { lock.withLock { cancellations += 1 } }
    func run(_ request: CommandRequest) async throws -> CommandOutput {
        lock.withLock { requests += 1 }
        return CommandOutput()
    }
    func stream(_ request: CommandRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
