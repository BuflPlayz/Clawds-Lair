import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let busy = store.busyMessage {
            Text(busy)
        } else if let active = store.activeProfile {
            Text("Claude is open as \(active.name)")
        } else {
            Text("Claude isn't running")
        }
        Divider()

        ForEach(store.profiles) { profile in
            Button {
                store.switchTo(profile)
            } label: {
                if store.activeID == profile.id {
                    Label(profile.name, systemImage: "checkmark")
                } else {
                    Text(profile.name)
                }
            }
            .disabled(store.busyMessage != nil)
        }

        Divider()
        Button("Open Clawd's Lair…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "switcher")
        }
        .keyboardShortcut("o")
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit Clawd's Lair") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
