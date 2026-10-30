import AppKit
import SwiftUI

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let appSupport = home.appendingPathComponent("Library/Application Support")
    /// The only folder signed Claude builds will use. The resident profile lives here.
    static var defaultClaudeData = appSupport.appendingPathComponent("Claude")
    /// Where the other profiles wait. Same volume as `defaultClaudeData`, so a swap is just two renames.
    /// Named after what the app was first called; existing installs keep their profiles here.
    static var switcherDir = appSupport.appendingPathComponent("ClaudeSwitcher")
    static var profilesDir: URL { switcherDir.appendingPathComponent("Profiles") }
    static var registry: URL { switcherDir.appendingPathComponent("profiles.json") }
    static var statsCache: URL { switcherDir.appendingPathComponent("stats-cache.json") }
    static let claudeProjects = home.appendingPathComponent(".claude/projects")
}

/// Warm, muted tones that sit with Claude's clay accent. Order matters: profiles store an index.
let profilePalette: [Color] = [
    .clay,
    Color(red: 0.42, green: 0.61, blue: 0.80), // sky
    Color(red: 0.61, green: 0.53, blue: 0.84), // lavender
    Color(red: 0.47, green: 0.55, blue: 0.36), // olive
    Color(red: 0.80, green: 0.45, blue: 0.56), // rose
    Color(red: 0.33, green: 0.62, blue: 0.60), // teal
    Color(red: 0.48, green: 0.50, blue: 0.82), // indigo
    Color(red: 0.76, green: 0.33, blue: 0.29), // brick
]

struct Profile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var colorIndex: Int
    /// Folder name under Profiles/ while this profile is not the one in Claude's folder.
    var folderName: String
    var createdAt: Date

    var color: Color { profilePalette[colorIndex % profilePalette.count] }
    var storedURL: URL { Paths.profilesDir.appendingPathComponent(folderName) }

    static func new(name: String, colorIndex: Int) -> Profile {
        let id = UUID()
        return Profile(id: id, name: name, colorIndex: colorIndex,
                       folderName: id.uuidString, createdAt: Date())
    }
}

struct Registry: Codable {
    var profiles: [Profile]
    /// The profile currently sitting in Claude's own folder.
    var residentID: UUID?

    static func load() -> Registry {
        var reg = (try? Data(contentsOf: Paths.registry))
            .flatMap { try? JSONDecoder.iso.decode(Registry.self, from: $0) }
            ?? Registry(profiles: [.new(name: "Main", colorIndex: 0)])
        reg.reconcile()
        return reg
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Paths.switcherDir, withIntermediateDirectories: true)
        try JSONEncoder.iso.encode(self).write(to: Paths.registry, options: .atomic)
    }

    func dataURL(_ profile: Profile) -> URL {
        profile.id == residentID ? Paths.defaultClaudeData : profile.storedURL
    }

    /// Works out which profile is in Claude's folder from what is actually on disk, so an
    /// interrupted swap or a lost registry can't point at the wrong folder.
    /// The resident profile is the one whose stored folder is missing.
    mutating func reconcile() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Paths.defaultClaudeData.path) else {
            residentID = nil
            return
        }
        let missing = profiles.filter { !fm.fileExists(atPath: $0.storedURL.path) }
        if let current = residentID, missing.contains(where: { $0.id == current }) {
            return
        }
        if let only = missing.first {
            residentID = only.id
        } else {
            // Claude's folder belongs to none of our profiles (e.g. Claude made a fresh one). Keep it as its own profile.
            let recovered = Profile.new(name: "Recovered", colorIndex: profiles.count)
            profiles.append(recovered)
            residentID = recovered.id
        }
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// The last stats that finished loading, so the window can show them straight away at launch
/// while fresh ones are worked out from the transcripts.
enum StatsCache {
    static func load() -> [UUID: ProfileStats] {
        (try? Data(contentsOf: Paths.statsCache))
            .flatMap { try? JSONDecoder.iso.decode([UUID: ProfileStats].self, from: $0) } ?? [:]
    }

    static func save(_ stats: [UUID: ProfileStats]) {
        try? JSONEncoder.iso.encode(stats).write(to: Paths.statsCache, options: .atomic)
    }
}

enum SwapError: LocalizedError {
    case claudeStillRunning
    case missingProfileFolder(String)
    case stashOccupied(String)

    var errorDescription: String? {
        switch self {
        case .claudeStillRunning: "Claude is running, so its folder can't be swapped."
        case .missingProfileFolder(let name): "The folder for \(name) is missing."
        case .stashOccupied(let path): "Something is already stored at \(path). Nothing was moved."
        }
    }
}

enum FolderSwap {
    /// Moves the resident profile's folder into storage and the target's folder into Claude's place.
    /// Claude must not be running. Rolls the first move back if the second fails.
    static func swap(_ registry: inout Registry, to target: Profile,
                     claudeIsRunning: () -> Bool = { !ClaudeLauncher.runningClaude().isEmpty }) throws {
        let fm = FileManager.default
        registry.reconcile()
        guard registry.residentID != target.id else { return }
        guard fm.fileExists(atPath: target.storedURL.path) else { throw SwapError.missingProfileFolder(target.name) }
        guard !claudeIsRunning() else { throw SwapError.claudeStillRunning }

        var movedOut: (from: URL, to: URL)?
        if let resident = registry.profiles.first(where: { $0.id == registry.residentID }) {
            let stash = resident.storedURL
            guard !fm.fileExists(atPath: stash.path) else { throw SwapError.stashOccupied(stash.path) }
            try fm.createDirectory(at: Paths.profilesDir, withIntermediateDirectories: true)
            try fm.moveItem(at: Paths.defaultClaudeData, to: stash)
            movedOut = (Paths.defaultClaudeData, stash)
        }
        do {
            try fm.moveItem(at: target.storedURL, to: Paths.defaultClaudeData)
        } catch {
            if let m = movedOut { try? fm.moveItem(at: m.to, to: m.from) }
            registry.reconcile()
            throw error
        }
        registry.residentID = target.id
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var stats: [UUID: ProfileStats] = [:]
    /// Each account's profile picture, when Claude has cached one.
    @Published private(set) var avatars: [UUID: NSImage] = [:]
    /// The main colors of each profile picture, for the portrait card's header glow.
    @Published private(set) var avatarColors: [UUID: [Color]] = [:]
    @Published private(set) var residentID: UUID?
    @Published private(set) var isClaudeRunning = false
    @Published private(set) var isLoadingStats = false
    /// True until the first fresh load finishes, while `stats` still holds what was cached last time.
    @Published private(set) var isShowingCachedStats = false
    @Published var busyMessage: String?
    @Published var errorMessage: String?

    private var registry: Registry
    private var observers: [NSObjectProtocol] = []

    init() {
        registry = Registry.load()
        try? FileManager.default.createDirectory(at: Paths.profilesDir, withIntermediateDirectories: true)
        try? registry.save()
        publish()
        loadCachedStats()
        refreshActive()
        refreshStats()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == ClaudeLauncher.bundleID else { return }
                MainActor.assumeIsolated { self?.refreshActive() }
            })
        }
        QuickSwitcher.shared.start(store: self)
    }

    /// The profile open in Claude right now, if Claude is running.
    var activeID: UUID? { isClaudeRunning ? residentID : nil }
    var activeProfile: Profile? { profiles.first { $0.id == activeID } }

    func dataURL(_ profile: Profile) -> URL { registry.dataURL(profile) }

    private func publish() {
        profiles = registry.profiles
        residentID = registry.residentID
    }

    func refreshActive() {
        isClaudeRunning = !ClaudeLauncher.runningClaude().isEmpty
        let before = (registry.profiles.count, registry.residentID)
        registry.reconcile()
        if before != (registry.profiles.count, registry.residentID) {
            try? registry.save()
            publish()
        }
    }

    private func loadCachedStats() {
        let ids = Set(profiles.map(\.id))
        let cached = StatsCache.load().filter { ids.contains($0.key) }
        guard !cached.isEmpty else { return }
        stats = cached
        isShowingCachedStats = true
        // Saved profile pictures don't depend on Claude's cache, so they can show right away too.
        let pictures = cached.compactMapValues { stats -> URL? in
            guard let account = stats.accountID else { return nil }
            let url = AccountAvatars.savedURL(accountID: account)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        setAvatars(pictures)
    }

    private func setAvatars(_ pictures: [UUID: URL]) {
        avatars = pictures.compactMapValues { NSImage(contentsOf: $0) }
        avatarColors = avatars.mapValues { AccountAvatars.palette(of: $0).map(Color.init(nsColor:)) }
    }

    func refreshStats() {
        guard !isLoadingStats else { return }
        isLoadingStats = true
        let targets = profiles.map { ($0.id, registry.dataURL($0)) }
        DispatchQueue.global(qos: .utility).async {
            var out: [UUID: ProfileStats] = [:]
            var pictures: [UUID: URL] = [:]
            for (id, url) in targets {
                let stats = StatsEngine.shared.compute(dataURL: url)
                out[id] = stats
                if let account = stats.accountID {
                    pictures[id] = AccountAvatars.refresh(dataURL: url, accountID: account)
                }
            }
            StatsCache.save(out)
            Task { @MainActor in
                self.stats = out
                self.setAvatars(pictures)
                self.isShowingCachedStats = false
                self.isLoadingStats = false
            }
        }
    }

    // MARK: Switching

    /// Switches Claude to `profile`. Clicks ask first when that means quitting Claude; the
    /// keyboard switcher passes `confirm: false` so it switches straight away.
    func switchTo(_ profile: Profile, confirm: Bool = true) {
        guard busyMessage == nil else { return }
        refreshActive()
        if profile.id == residentID {
            if isClaudeRunning {
                ClaudeLauncher.activateClaude()
            } else {
                Task { await openClaude() }
            }
            return
        }
        if isClaudeRunning && confirm {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Switch to \(profile.name)?"
            alert.informativeText = "Claude will quit and reopen on this account. Anything running in Claude right now, including Claude Code sessions, will stop. Your chats and settings stay saved."
            alert.addButton(withTitle: "Quit & Switch")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        Task {
            busyMessage = "Quitting Claude…"
            guard await ClaudeLauncher.quitClaude(timeout: 15) else {
                busyMessage = nil
                errorMessage = "Claude didn't quit. It may be waiting for you to confirm something. Quit it yourself, then try again."
                return
            }
            busyMessage = "Swapping to \(profile.name)…"
            do {
                try FolderSwap.swap(&registry, to: profile)
                try registry.save()
            } catch {
                errorMessage = "Couldn't switch: \(error.localizedDescription)"
            }
            publish()
            await openClaude()
            refreshStats()
        }
    }

    private func openClaude() async {
        busyMessage = "Opening Claude…"
        do {
            try await ClaudeLauncher.launch()
        } catch {
            errorMessage = "Couldn't open Claude: \(error.localizedDescription)"
        }
        busyMessage = nil
        refreshActive()
    }

    // MARK: Editing

    @discardableResult
    func addProfile(name: String, colorIndex: Int) -> Profile? {
        let profile = Profile.new(name: name, colorIndex: colorIndex)
        do {
            try FileManager.default.createDirectory(at: profile.storedURL, withIntermediateDirectories: true)
            registry.profiles.append(profile)
            try registry.save()
        } catch {
            errorMessage = "Couldn't create the account folder: \(error.localizedDescription)"
            return nil
        }
        publish()
        stats[profile.id] = ProfileStats()
        return profile
    }

    func update(_ profile: Profile) {
        guard let i = registry.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        registry.profiles[i] = profile
        try? registry.save()
        publish()
    }

    func remove(_ profile: Profile) {
        guard profile.id != residentID else {
            errorMessage = "\(profile.name) is the account in Claude's folder right now. Switch to another account first."
            return
        }
        // Move to the Trash rather than deleting, so it can be restored.
        NSWorkspace.shared.recycle([profile.storedURL]) { _, error in
            Task { @MainActor in
                if let error, FileManager.default.fileExists(atPath: profile.storedURL.path) {
                    self.errorMessage = "Couldn't move the folder to the Trash: \(error.localizedDescription)"
                    return
                }
                self.registry.profiles.removeAll { $0.id == profile.id }
                try? self.registry.save()
                self.publish()
                self.stats[profile.id] = nil
            }
        }
    }

    func reveal(_ profile: Profile) {
        NSWorkspace.shared.activateFileViewerSelecting([registry.dataURL(profile)])
    }
}
