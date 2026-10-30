import AppKit
import SwiftUI

/// The keyboard account switcher. With two accounts the shortcut flips straight to the other
/// one. With more, it opens a panel like ⌘⇥: keep holding the modifier and press the key again
/// to move along (add ⇧ to go back), then let go to switch. Esc cancels.
@MainActor
final class QuickSwitcher: ObservableObject {
    static let shared = QuickSwitcher()

    /// Accounts in the panel, captured when it opens.
    @Published private(set) var profiles: [Profile] = []
    @Published var selected = 0
    /// Set for the short "Switching to…" notice shown when there are only two accounts.
    @Published private(set) var notice: Profile?
    /// True when the saved shortcut couldn't be registered, usually because another app has it.
    @Published private(set) var registrationFailed = false

    private(set) weak var store: ProfileStore?
    private var shortcut: Shortcut?
    private var cycling = false
    private var modifierWatch: Timer?
    private var noticeTimer: Timer?
    private var panel: NSPanel?
    private var defaultsObserver: NSObjectProtocol?

    /// Turns the shortcut off while Settings records a new one, so pressing the old one there
    /// doesn't switch accounts.
    var paused = false {
        didSet { if paused != oldValue { register() } }
    }

    private enum ID {
        static let forward: UInt32 = 1
        static let backward: UInt32 = 2
        static let cancel: UInt32 = 3
    }

    func start(store: ProfileStore) {
        self.store = store
        reload()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        #if DEBUG
        runDemoIfAsked()
        #endif
    }

    #if DEBUG
    /// `--demo-switcher` (debug builds only): steps the picker through the accounts, then shows
    /// the two-account notice, without switching anything. For checking the panel's look.
    private func runDemoIfAsked() {
        guard CommandLine.arguments.contains("--demo-switcher") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let store = self.store else { return }
            self.profiles = store.profiles
            self.selected = 0
            self.notice = nil
            self.cycling = true
            self.showPanel()
            var steps = 0
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { timer in
                MainActor.assumeIsolated {
                    steps += 1
                    if steps < 3 {
                        self.step(1)
                    } else {
                        timer.invalidate()
                        self.cycling = false
                        if let first = store.profiles.first { self.showNotice(first) }
                    }
                }
            }
        }
    }
    #endif

    private func reload() {
        let saved = Shortcut.saved
        guard saved != shortcut else { return }
        shortcut = saved
        register()
    }

    private func register() {
        HotKeys.shared.unregister(ID.forward)
        HotKeys.shared.unregister(ID.backward)
        guard !paused, let shortcut else {
            registrationFailed = false
            return
        }
        registrationFailed = !HotKeys.shared.register(ID.forward, keyCode: shortcut.keyCode,
                                                      modifiers: shortcut.carbonModifiers) { [weak self] in
            self?.pressed(reverse: false)
        }
        if !shortcut.modifiers.contains(.shift) {
            HotKeys.shared.register(ID.backward, keyCode: shortcut.keyCode,
                                    modifiers: shortcut.carbonModifiers | Shortcut.carbon(.shift)) { [weak self] in
                self?.pressed(reverse: true)
            }
        }
    }

    // MARK: Pressing

    private func pressed(reverse: Bool) {
        if cycling {
            step(reverse ? -1 : 1)
            return
        }
        guard let store, store.busyMessage == nil, store.profiles.count >= 2 else {
            NSSound.beep()
            return
        }
        let list = store.profiles
        let current = list.firstIndex { $0.id == store.residentID } ?? 0

        if list.count == 2 {
            let target = list[(current + 1) % 2]
            showNotice(target)
            store.switchTo(target, confirm: false)
            return
        }

        profiles = list
        selected = (current + (reverse ? -1 : 1) + list.count) % list.count
        notice = nil
        cycling = true
        showPanel()
        watchModifiers()
        if let shortcut {
            HotKeys.shared.register(ID.cancel, keyCode: UInt16(53), modifiers: Shortcut.carbon(shortcut.holdModifiers)) { [weak self] in
                self?.finish(switching: false)
            }
        }
    }

    private func step(_ delta: Int) {
        guard !profiles.isEmpty else { return }
        selected = (selected + delta + profiles.count) % profiles.count
    }

    /// Picks an account by clicking its tile.
    func choose(_ index: Int) {
        selected = index
        finish(switching: true)
    }

    /// Polls the modifier keys: reading them needs no permission, unlike watching key events
    /// in other apps. Letting go of the shortcut's modifiers commits the choice.
    private func watchModifiers() {
        modifierWatch?.invalidate()
        modifierWatch = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let shortcut = self.shortcut else { return }
                if !NSEvent.modifierFlags.contains(shortcut.holdModifiers) { self.finish(switching: true) }
            }
        }
    }

    private func finish(switching: Bool) {
        guard cycling else { return }
        cycling = false
        modifierWatch?.invalidate()
        modifierWatch = nil
        HotKeys.shared.unregister(ID.cancel)
        let target = profiles.indices.contains(selected) ? profiles[selected] : nil
        hidePanel()
        if switching, let target { store?.switchTo(target, confirm: false) }
    }

    private func showNotice(_ profile: Profile) {
        notice = profile
        showPanel()
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.cycling else { return }
                self.hidePanel()
            }
        }
    }

    // MARK: Panel

    private func showPanel() {
        guard let store else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: SwitcherHUD(switcher: self, store: store))
        panel.contentView = host
        let size = host.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.08,
                                  width: size.width, height: size.height), display: true)
        }
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                if !self.cycling && panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }
}

// MARK: - HUD

private struct SwitcherHUD: View {
    @ObservedObject var switcher: QuickSwitcher
    @ObservedObject var store: ProfileStore

    private let tileWidth: CGFloat = 112
    private let spacing: CGFloat = 8
    private let maxVisible = 6

    var body: some View {
        Group {
            if let profile = switcher.notice {
                notice(profile)
            } else {
                picker
            }
        }
        .padding(24) // room for the glass shadow inside the borderless panel
    }

    private func notice(_ profile: Profile) -> some View {
        HStack(spacing: 14) {
            ProfileAvatar(profile: profile, image: store.avatars[profile.id], size: 48, square: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Switching to").font(.sans(12)).foregroundStyle(Color.textSecondary)
                Text(profile.name).font(.serif(22))
            }
            SparkView(state: .writing, size: 26, color: profile.color)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    private var picker: some View {
        let count = switcher.profiles.count
        let visible = min(count, maxVisible)
        let width = CGFloat(visible) * tileWidth + CGFloat(max(visible - 1, 0)) * spacing
        return VStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(Array(switcher.profiles.enumerated()), id: \.element.id) { index, profile in
                            tile(profile, selected: index == switcher.selected)
                                .id(index)
                                .onTapGesture { switcher.choose(index) }
                        }
                    }
                }
                .frame(width: width)
                .scrollDisabled(count <= maxVisible)
                .onAppear { proxy.scrollTo(switcher.selected, anchor: .center) }
                .onChange(of: switcher.selected) { _, index in
                    withAnimation(.smooth(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) }
                }
            }
            Text("Release to switch · esc to cancel")
                .font(.sans(11))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    private func tile(_ profile: Profile, selected: Bool) -> some View {
        let isResident = store.residentID == profile.id
        return VStack(spacing: 8) {
            ProfileAvatar(profile: profile, image: store.avatars[profile.id], size: 72, square: true)
                .scaleEffect(selected ? 1.04 : 1)
            Text(profile.name)
                .font(.sans(13, selected ? .semibold : .medium))
                .lineLimit(1)
            HStack(spacing: 4) {
                if isResident {
                    Circle().fill(store.isClaudeRunning ? Color.green : Color.textTertiary).frame(width: 5, height: 5)
                }
                Text(isResident ? (store.isClaudeRunning ? "Open now" : "Last used") : " ")
                    .font(.sans(10))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(width: tileWidth - 20)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(selected ? profile.color.opacity(0.3) : .clear)
        )
        .contentShape(.rect(cornerRadius: 20))
        .animation(.smooth(duration: 0.18), value: selected)
    }
}
