import AppKit

enum ClaudeLauncher {
    static let bundleID = "com.anthropic.claudefordesktop"

    enum LaunchError: LocalizedError {
        case notInstalled
        var errorDescription: String? { "Claude.app wasn't found." }
    }

    static func runningClaude() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
    }

    static func activateClaude() {
        runningClaude().first?.activate()
    }

    /// Asks Claude to quit normally and waits for it. Never force-kills.
    static func quitClaude(timeout: TimeInterval) async -> Bool {
        let apps = runningClaude()
        guard !apps.isEmpty else { return true }
        apps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if runningClaude().isEmpty {
                // Give helper processes a moment to finish writing and exit.
                try? await Task.sleep(for: .seconds(1))
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    static func launch() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw LaunchError.notInstalled
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
