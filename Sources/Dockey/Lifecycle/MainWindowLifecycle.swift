import AppKit
import SwiftUI

@MainActor
protocol DockeyMainWindow: AnyObject {
    var isVisible: Bool { get }
    var isMiniaturized: Bool { get }
    func hideDockeyWindow()
    func showDockeyWindow()
}

extension NSWindow: DockeyMainWindow {
    func hideDockeyWindow() { orderOut(nil) }
    func showDockeyWindow() {
        if isMiniaturized { deminiaturize(nil) }
        makeKeyAndOrderFront(nil)
    }
}

/// Owns no window. SwiftUI's single Window scene retains its normal ownership and delegate.
@MainActor
final class MainWindowLifecycle: NSObject {
    private(set) weak var window: (any DockeyMainWindow)?
    private var proxy: WindowDelegateProxy?
    private weak var observedWindow: NSWindow?
    private(set) var isTerminating = false
    var visibilityChanged: ((Bool) -> Void)?
    private let activate: () -> Void

    init(activate: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) }) {
        self.activate = activate
        super.init()
    }

    func attach(_ window: any DockeyMainWindow) {
        if self.window === window {
            // SwiftUI may update its own delegate during scene setup.
            if let native = window as? NSWindow { installProxy(on: native) }
            updateVisibility(applicationHidden: NSApp?.isHidden ?? false)
            return
        }
        detach()
        self.window = window
        if let native = window as? NSWindow {
            observedWindow = native
            installProxy(on: native)
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification, NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(windowStateChanged(_:)), name: name, object: native)
            }
        }
        updateVisibility(applicationHidden: NSApp?.isHidden ?? false)
    }

    private func installProxy(on window: NSWindow) {
        if let proxy, window.delegate === proxy { return }
        let replacement = WindowDelegateProxy(original: window.delegate) { [weak self] _ in self?.hide() }
        proxy = replacement
        window.delegate = replacement
    }

    func detach() {
        if let native = observedWindow {
            NotificationCenter.default.removeObserver(self, name: nil, object: native)
            if native.delegate === proxy { native.delegate = proxy?.originalDelegate }
        }
        observedWindow = nil
        proxy = nil
        window = nil
    }

    func hide() {
        guard !isTerminating else { return }
        window?.hideDockeyWindow()
        visibilityChanged?(false)
    }

    @discardableResult
    func show() -> Bool {
        guard !isTerminating, let window else { return false }
        window.showDockeyWindow()
        activate()
        updateVisibility()
        return true
    }

    func updateVisibility(applicationHidden: Bool = false) {
        visibilityChanged?(!isTerminating && !applicationHidden && window?.isVisible == true && window?.isMiniaturized == false)
    }

    func prepareForTermination() {
        isTerminating = true
        visibilityChanged?(false)
    }

    @objc private func windowStateChanged(_ notification: Notification) {
        if notification.name == NSWindow.willCloseNotification {
            visibilityChanged?(false)
        } else {
            updateVisibility(applicationHidden: NSApp?.isHidden ?? false)
        }
    }
}

/// Only intercept user close. Objective-C optional delegate methods continue to SwiftUI.
/// AppKit invokes window delegate callbacks on the main thread; no delegate or window is retained here.
final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    private(set) weak var originalDelegate: (any NSWindowDelegate)?
    private let hide: @MainActor (NSWindow) -> Void

    @MainActor
    init(original: (any NSWindowDelegate)?, hide: @escaping @MainActor (NSWindow) -> Void) {
        originalDelegate = original
        self.hide = hide
        super.init()
    }

    @MainActor
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide(sender)
        return false
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if originalDelegate?.responds(to: selector) == true { return originalDelegate }
        return super.forwardingTarget(for: selector)
    }
}

struct WindowBridge: NSViewRepresentable {
    let lifecycle: MainWindowLifecycle

    func makeNSView(context: Context) -> WindowCaptureView {
        WindowCaptureView(lifecycle: lifecycle)
    }
    func updateNSView(_ view: WindowCaptureView, context: Context) {
        if let window = view.window { lifecycle.attach(window) }
    }
    static func dismantleNSView(_ view: WindowCaptureView, coordinator: ()) { view.lifecycle?.detach() }

    final class WindowCaptureView: NSView {
        weak var lifecycle: MainWindowLifecycle?
        init(lifecycle: MainWindowLifecycle) {
            self.lifecycle = lifecycle
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { lifecycle?.attach(window) }
        }
    }
}
