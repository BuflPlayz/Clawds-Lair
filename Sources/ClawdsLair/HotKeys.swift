import AppKit
import Carbon.HIToolbox

/// A key combination for the account switcher, stored in UserDefaults as a string.
struct Shortcut: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    /// What to show for the key itself, e.g. "⇥" or "K".
    var key: String

    static let storageKey = "switchShortcut"
    /// Stored when the shortcut is turned off.
    static let off = "off"
    static let defaultValue = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.option], key: "⇥")

    /// The modifiers a shortcut can use; shift is allowed but on its own isn't enough.
    private static let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevant)
        self.key = key
    }

    /// A shortcut from a key press, if it has a modifier other than shift.
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Self.relevant)
        guard !modifiers.intersection([.control, .option, .command]).isEmpty else { return nil }
        let key = Self.keyNames[Int(event.keyCode)]
            ?? event.charactersIgnoringModifiers?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else { return nil }
        self.init(keyCode: event.keyCode, modifiers: modifiers, key: key)
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 2).map(String.init)
        guard parts.count == 3, let code = UInt16(parts[0]), let mods = UInt(parts[1]) else { return nil }
        self.init(keyCode: code, modifiers: NSEvent.ModifierFlags(rawValue: mods), key: parts[2])
    }

    var rawValue: String { "\(keyCode)|\(modifiers.rawValue)|\(key)" }

    /// The shortcut currently saved in Settings, or nil when it's turned off.
    static var saved: Shortcut? {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? defaultValue.rawValue
        return Shortcut(rawValue: raw)
    }

    /// Mac-style label: ⌃⌥⇧⌘ then the key.
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key
    }

    /// The modifiers that must stay held while picking an account. Shift steps backwards, so
    /// letting go of it doesn't count.
    var holdModifiers: NSEvent.ModifierFlags { modifiers.subtracting(.shift) }

    var carbonModifiers: UInt32 { Self.carbon(modifiers) }

    static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    private static let keyNames: [Int: String] = [
        kVK_Tab: "⇥", kVK_Space: "Space", kVK_Return: "↩", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// System-wide hotkeys through Carbon's RegisterEventHotKey, which needs no Accessibility
/// permission. Events arrive on the main thread.
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false
    private let signature: OSType = 0x434C_5357 // "CLSW"

    /// Registers `keyCode` + `modifiers` under `id`, replacing anything already there. Returns
    /// false when the combination can't be taken, usually because another app owns it.
    @discardableResult
    func register(_ id: UInt32, keyCode: UInt16, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        installHandler()
        unregister(id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, EventHotKeyID(signature: signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        actions[id] = action
        return true
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        actions[id] = nil
    }

    fileprivate func fire(_ id: UInt32) { actions[id]?() }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            MainActor.assumeIsolated { HotKeys.shared.fire(id.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
