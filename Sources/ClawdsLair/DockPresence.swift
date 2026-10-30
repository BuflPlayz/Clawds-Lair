import AppKit

/// Shows the app in the Dock and the ⌘-Tab switcher only while one of its windows is open,
/// so with just the menu bar icon left it stays out of the way. The app starts as a menu bar
/// app (LSUIElement in Info.plist) and becomes a regular one when its first window opens.
enum DockPresence {
    nonisolated(unsafe) private static var observers: [NSObjectProtocol] = []

    static func start() {
        let center = NotificationCenter.default
        // A window opened while the app is still a menu bar app may never become key, but it
        // does change occlusion as it comes on screen.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { update() }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let closing = note.object as? NSWindow
            MainActor.assumeIsolated { update(closing: closing) }
        })
    }

    @MainActor
    private static func update(closing: NSWindow? = nil) {
        // Minimized windows count, or they'd vanish from the Dock along with the icon.
        // Panels (the keyboard switcher, alerts) and the menu bar's own windows don't.
        let hasWindow = NSApp.windows.contains { window in
            window !== closing && !(window is NSPanel) && window.styleMask.contains(.titled)
                && (window.isVisible || window.isMiniaturized)
        }
        let policy: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Turning back into a regular app doesn't bring it forward by itself.
        if hasWindow { NSApp.activate(ignoringOtherApps: true) }
    }
}
