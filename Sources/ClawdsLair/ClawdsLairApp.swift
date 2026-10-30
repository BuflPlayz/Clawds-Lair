import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--dump-stats") {
            dumpStats()
            return
        }
        ClaudeFonts.register()
        ClaudeArt.prepare()
        LoginItem.enableOnFirstRun()
        DockPresence.start()
        ClawdsLairApp.main()
    }

    /// Debug helper: prints every profile's stats as JSON without opening any UI.
    private static func dumpStats() {
        struct Row: Encodable {
            let name: String
            let folder: String
            let topModel: String?
            let stats: ProfileStats
        }
        let registry = Registry.load()
        let rows = registry.profiles.map { p in
            let url = registry.dataURL(p)
            let s = StatsEngine.shared.compute(dataURL: url)
            return Row(name: p.name, folder: url.path, topModel: s.topModel, stats: s)
        }
        if let data = try? JSONEncoder.iso.encode(rows) {
            print(String(decoding: data, as: UTF8.self))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard LoginItem.wasLaunchedAtLogin else { return }
        // At login the app only goes in the menu bar. It starts without a Dock icon (LSUIElement),
        // but SwiftUI opens the main window as it launches, so close it before it's drawn.
        DispatchQueue.main.async {
            for window in NSApp.windows where window.styleMask.contains(.titled) && !(window is NSPanel) {
                window.close()
            }
        }
    }
}

struct ClawdsLairApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var store = ProfileStore()

    var body: some Scene {
        Window("Clawd's Lair", id: "switcher") {
            AccountsWindow()
                .environmentObject(store)
        }
        // Opens centered on screen every time, rather than wherever the last frame was saved:
        // a saved frame keeps any offset left behind when the content trimmed the window's size.
        .defaultWindowPlacement { _, context in
            let visible = context.defaultDisplay.visibleRect
            return WindowPlacement(.center, size: CGSize(width: min(760, visible.width),
                                                         height: min(860, visible.height)))
        }
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuContent()
                .environmentObject(store)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }
}
