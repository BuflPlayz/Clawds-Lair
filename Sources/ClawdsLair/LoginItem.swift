import AppKit
import ServiceManagement

/// Opens the app when you log in, through macOS's own Login Items list.
enum LoginItem {
    private static let setUpKey = "loginItemSetUp"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Whether macOS opened the app as a login item. Only reliable while the app finishes
    /// launching, when the event that opened it is still current. `--as-login-item` fakes it.
    @MainActor static var wasLaunchedAtLogin: Bool {
        if CommandLine.arguments.contains("--as-login-item") { return true }
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Turns it on the first time the installed app runs; after that it's the toggle in Settings.
    /// Builds run from elsewhere (like ./build) are skipped, since Login Items opens the copy
    /// that registered.
    static func enableOnFirstRun() {
        guard !UserDefaults.standard.bool(forKey: setUpKey), isInstalled else { return }
        if (try? setEnabled(true)) != nil {
            UserDefaults.standard.set(true, forKey: setUpKey)
        }
    }

    private static var isInstalled: Bool {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL
        let applications = [Paths.home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/Applications")]
        return applications.contains { $0.standardizedFileURL == folder }
    }
}
