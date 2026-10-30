import XCTest
@testable import ClawdsLair

/// Runs the swap against throwaway folders; the real Claude folder is never touched.
final class FolderSwapTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    private let notRunning: () -> Bool = { false }

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("swaptest-\(UUID().uuidString)")
        Paths.defaultClaudeData = root.appendingPathComponent("Claude")
        Paths.switcherDir = root.appendingPathComponent("ClaudeSwitcher")
        try fm.createDirectory(at: Paths.profilesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: Paths.defaultClaudeData, withIntermediateDirectories: true)
        try mark(Paths.defaultClaudeData, "main")
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func mark(_ dir: URL, _ text: String) throws {
        try text.write(to: dir.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
    }

    private func marker(_ dir: URL) -> String? {
        try? String(contentsOf: dir.appendingPathComponent("marker"), encoding: .utf8)
    }

    private func addStored(_ reg: inout Registry, _ name: String) throws -> Profile {
        let p = Profile.new(name: name, colorIndex: 0)
        try fm.createDirectory(at: p.storedURL, withIntermediateDirectories: true)
        try mark(p.storedURL, name)
        reg.profiles.append(p)
        return p
    }

    func testFreshRegistryAdoptsClaudeFolderAsMain() {
        let reg = Registry.load()
        XCTAssertEqual(reg.profiles.count, 1)
        XCTAssertEqual(reg.residentID, reg.profiles[0].id)
        XCTAssertEqual(reg.dataURL(reg.profiles[0]), Paths.defaultClaudeData)
    }

    func testSwapThereAndBack() throws {
        var reg = Registry.load()
        let main = reg.profiles[0]
        let work = try addStored(&reg, "work")

        try FolderSwap.swap(&reg, to: work, claudeIsRunning: notRunning)
        XCTAssertEqual(reg.residentID, work.id)
        XCTAssertEqual(marker(Paths.defaultClaudeData), "work")
        XCTAssertEqual(marker(main.storedURL), "main")
        XCTAssertFalse(fm.fileExists(atPath: work.storedURL.path))

        try FolderSwap.swap(&reg, to: main, claudeIsRunning: notRunning)
        XCTAssertEqual(reg.residentID, main.id)
        XCTAssertEqual(marker(Paths.defaultClaudeData), "main")
        XCTAssertEqual(marker(work.storedURL), "work")
    }

    func testRefusesWhileClaudeRuns() throws {
        var reg = Registry.load()
        let work = try addStored(&reg, "work")
        XCTAssertThrowsError(try FolderSwap.swap(&reg, to: work, claudeIsRunning: { true }))
        XCTAssertEqual(marker(Paths.defaultClaudeData), "main")
        XCTAssertEqual(marker(work.storedURL), "work")
    }

    func testRecoversFromInterruptedSwap() throws {
        var reg = Registry.load()
        let main = reg.profiles[0]
        let work = try addStored(&reg, "work")
        // Simulate a crash after the first rename: Claude's folder was stashed, nothing moved in.
        try fm.moveItem(at: Paths.defaultClaudeData, to: main.storedURL)

        reg.reconcile()
        XCTAssertNil(reg.residentID)

        try FolderSwap.swap(&reg, to: work, claudeIsRunning: notRunning)
        XCTAssertEqual(marker(Paths.defaultClaudeData), "work")
        XCTAssertEqual(marker(main.storedURL), "main")
    }

    func testRegistryFollowsDiskAfterCrashBeforeSave() throws {
        var reg = Registry.load()
        let work = try addStored(&reg, "work")
        try reg.save()
        try FolderSwap.swap(&reg, to: work, claudeIsRunning: notRunning)
        // Don't save: the registry on disk still says Main is resident.
        let reloaded = Registry.load()
        XCTAssertEqual(reloaded.residentID, work.id)
    }

    func testUnknownClaudeFolderBecomesRecoveredProfile() throws {
        var reg = Registry.load()
        let main = reg.profiles[0]
        _ = try addStored(&reg, "work")
        // Main gets stored and Claude makes a brand-new folder on its own.
        try fm.moveItem(at: Paths.defaultClaudeData, to: main.storedURL)
        try fm.createDirectory(at: Paths.defaultClaudeData, withIntermediateDirectories: true)

        reg.reconcile()
        XCTAssertEqual(reg.profiles.count, 3)
        XCTAssertEqual(reg.profiles.last?.name, "Recovered")
        XCTAssertEqual(reg.residentID, reg.profiles.last?.id)
    }
}
