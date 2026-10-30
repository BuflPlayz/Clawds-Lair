import SwiftUI

/// How account cards are drawn.
enum CardStyle: String, CaseIterable, Identifiable {
    /// A small avatar beside the name.
    case compact
    /// The whole square profile picture, large, beside the name.
    case portrait

    static let storageKey = "cardStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .portrait: "Portrait"
        }
    }

    var detail: String {
        switch self {
        case .compact: "Small picture next to the name. Fits the most on screen."
        case .portrait: "Your whole profile picture, large, beside the name."
        }
    }
}

struct SettingsView: View {
    @AppStorage(CardStyle.storageKey) private var cardStyle: CardStyle = .compact
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account cards").font(.serif(22))
            HStack(spacing: 12) {
                ForEach(CardStyle.allCases) { style in
                    StyleOption(style: style, selected: cardStyle == style) {
                        withAnimation(.smooth(duration: 0.3)) { cardStyle = style }
                    }
                }
            }

            Text("Switch shortcut").font(.serif(22)).padding(.top, 10)
            ShortcutRecorder()
            Text("Works from any app. With two accounts it switches straight to the other one. With more, keep holding the modifier and press the key again to move through them, add ⇧ to go back, then let go to switch. Switching this way quits and reopens Claude without asking first.")
                .font(.sans(11))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Startup").font(.serif(22)).padding(.top, 10)
            Toggle("Open Clawd's Lair when you log in", isOn: $opensAtLogin)
                .font(.sans(13))
                .onChange(of: opensAtLogin) { _, enabled in
                    guard enabled != LoginItem.isEnabled else { return }
                    do {
                        try LoginItem.setEnabled(enabled)
                        loginItemError = nil
                    } catch {
                        loginItemError = "Couldn't change this: \(error.localizedDescription) You can also add it in System Settings › General › Login Items."
                        opensAtLogin = LoginItem.isEnabled
                    }
                }
            if let loginItemError {
                Text(loginItemError)
                    .font(.sans(11))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Color.canvas)
    }
}

private struct StyleOption: View {
    let style: CardStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title).font(.sans(13, .semibold))
                    Text(style.detail)
                        .font(.sans(11))
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Color.clay : .clear, lineWidth: 2)
        )
    }

    /// A tiny sketch of the card layout.
    @ViewBuilder
    private var preview: some View {
        let bar = Color.primary.opacity(0.12)
        switch style {
        case .compact:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(Color.clay.opacity(0.6)).frame(width: 18, height: 18)
                    Capsule().fill(bar).frame(width: 52, height: 7)
                }
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(bar).frame(height: 16) }
                }
                Capsule().fill(bar).frame(height: 5)
                Capsule().fill(bar).frame(width: 80, height: 5)
            }
            .padding(12)
        case .portrait:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.clay.opacity(0.7))
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(bar).frame(width: 52, height: 7)
                        Capsule().fill(bar).frame(width: 36, height: 5)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(bar).frame(height: 14) }
                }
                Capsule().fill(bar).frame(height: 5)
            }
            .padding(12)
        }
    }
}

/// Click, then press a key combination to set the switcher shortcut.
private struct ShortcutRecorder: View {
    @AppStorage(Shortcut.storageKey) private var raw = Shortcut.defaultValue.rawValue
    @ObservedObject private var switcher = QuickSwitcher.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var rejected = false

    private var shortcut: Shortcut? { Shortcut(rawValue: raw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: toggle) {
                    Text(label)
                        .font(.sans(14, .semibold))
                        .foregroundStyle(recording ? Color.white : Color.primary)
                        .frame(minWidth: 120)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(recording ? .regular.tint(.clay).interactive() : .regular.interactive(), in: .capsule)
                .modifier(Shake(trigger: rejected))

                if recording {
                    Button("Cancel") { stop() }.buttonStyle(.glass)
                } else {
                    if shortcut != nil {
                        Button("Turn Off") { raw = Shortcut.off }.buttonStyle(.glass)
                    }
                    if raw != Shortcut.defaultValue.rawValue {
                        Button("Reset") { raw = Shortcut.defaultValue.rawValue }.buttonStyle(.glass)
                    }
                }
            }
            .font(.sans(12, .medium))
            .animation(.smooth(duration: 0.2), value: recording)

            if recording {
                Text("Press a key with ⌘, ⌥ or ⌃. Esc cancels.")
                    .font(.sans(11)).foregroundStyle(Color.textSecondary)
            } else if switcher.registrationFailed {
                Text("Another app is already using \(shortcut?.display ?? "this shortcut"). Pick a different one.")
                    .font(.sans(11)).foregroundStyle(.orange)
            }
        }
        .onDisappear { stop() }
    }

    private var label: String {
        if recording { return "Type shortcut…" }
        return shortcut?.display ?? "Off"
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        switcher.paused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                stop()
            } else if let new = Shortcut(event: event) {
                raw = new.rawValue
                stop()
            } else {
                rejected.toggle()
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        switcher.paused = false
    }
}

/// A small horizontal shake when a key press can't be used as a shortcut.
private struct Shake: ViewModifier {
    let trigger: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(-6, duration: 0.06)
                SpringKeyframe(6, duration: 0.08)
                SpringKeyframe(-3, duration: 0.08)
                SpringKeyframe(0, duration: 0.1)
            }
        }
    }
}
