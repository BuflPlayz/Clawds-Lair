import AppKit
import XCTest
@testable import ClawdsLair

/// Copies the art out of the installed Claude.app into a throwaway folder. Skipped without Claude.app.
final class ClaudeArtTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try XCTSkipIf(NSWorkspace.shared.urlForApplication(withBundleIdentifier: ClaudeLauncher.bundleID) == nil,
                      "Claude.app isn't installed")
        root = fm.temporaryDirectory.appendingPathComponent("arttest-\(UUID().uuidString)")
        Paths.switcherDir = root.appendingPathComponent("ClaudeSwitcher")
        try fm.createDirectory(at: Paths.switcherDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? fm.removeItem(at: root) }
    }

    @MainActor
    func testCopiesSparksAndClawd() throws {
        ClaudeArt.prepare()
        let sparks = try JSONSerialization.jsonObject(with: Data(contentsOf: ClaudeArt.sparks.appendingPathComponent("sparks.json"))) as? [String: Any]
        let clawd = try JSONSerialization.jsonObject(with: Data(contentsOf: ClaudeArt.clawd.appendingPathComponent("clawd.json"))) as? [String: Any]
        XCTAssertNotNil(sparks?["tickle"])
        XCTAssertNotNil(clawd?["Waving"])
        XCTAssertNotNil(SparkSprites.shared.strip(.thinking))
        XCTAssertNotNil(ClawdSprites.shared.strip(.waving))
        if let dump = ProcessInfo.processInfo.environment["CLAUDE_ART_DUMP"] {
            try? fm.removeItem(atPath: dump)
            try fm.copyItem(at: ClaudeArt.directory, to: URL(fileURLWithPath: dump))
        }
    }
}
