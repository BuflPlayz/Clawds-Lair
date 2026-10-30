import Foundation

struct TokenCounts: Codable, Hashable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var messages = 0

    var total: Int { input + output + cacheRead + cacheWrite }

    mutating func add(_ o: TokenCounts) {
        input += o.input
        output += o.output
        cacheRead += o.cacheRead
        cacheWrite += o.cacheWrite
        messages += o.messages
    }
}

struct PlanUsage: Codable, Hashable {
    /// Percent of the 5-hour limit used.
    var fiveHour: Int?
    /// Percent of the weekly limit used.
    var weekly: Int?
    var at: Date

    static let savedHelp = "Claude saves your plan usage every so often while it's open. Refreshing reads the latest it saved, so this only moves forward once Claude saves again."
}

struct ProfileStats: Codable {
    var accountID: String?
    var codeSessions = 0
    var coworkSessions = 0
    var totals = TokenCounts()
    var byModel: [String: TokenCounts] = [:]
    /// Local day ("yyyy-MM-dd") → total tokens.
    var daily: [String: Int] = [:]
    var lastActive: Date?
    var planUsage: PlanUsage?
    var folderBytes: Int64 = 0

    var topModel: String? { byModel.max { $0.value.total < $1.value.total }?.key }
    var sessions: Int { codeSessions + coworkSessions }
}

/// Reads token usage from local Claude Code / Cowork transcripts. Everything is read-only and local.
final class StatsEngine: @unchecked Sendable {
    static let shared = StatsEngine()

    private struct TranscriptUsage {
        var byModel: [String: TokenCounts] = [:]
        var daily: [String: Int] = [:]
    }

    private let lock = NSLock()
    private var cache: [String: (Date, TranscriptUsage)] = [:]
    private let fm = FileManager.default
    private let usageNeedle = Data("\"usage\"".utf8)
    private let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let iso = ISO8601DateFormatter()
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func compute(dataURL: URL) -> ProfileStats {
        lock.lock()
        defer { lock.unlock() }

        var stats = ProfileStats()
        if let config = readJSON(dataURL.appendingPathComponent("config.json")) {
            stats.accountID = config["lastKnownAccountUuid"] as? String
        }

        let globalIndex = transcriptIndex()
        let kinds = [("claude-code-sessions", false), ("local-agent-mode-sessions", true)]
        for (dirName, isCowork) in kinds {
            for sessionFile in sessionFiles(in: dataURL.appendingPathComponent(dirName)) {
                guard let session = readJSON(sessionFile),
                      let cliID = session["cliSessionId"] as? String else { continue }
                if isCowork { stats.coworkSessions += 1 } else { stats.codeSessions += 1 }
                if let ms = session["lastActivityAt"] as? Double {
                    let d = Date(timeIntervalSince1970: ms / 1000)
                    if stats.lastActive.map({ d > $0 }) ?? true { stats.lastActive = d }
                }
                // Cowork keeps transcripts inside the session's own folder; Code uses ~/.claude/projects.
                let localDir = sessionFile.deletingPathExtension().appendingPathComponent(".claude/projects")
                let transcripts = fm.fileExists(atPath: localDir.path)
                    ? jsonlFiles(under: localDir)
                    : globalIndex[cliID] ?? []
                for url in transcripts {
                    let usage = transcriptUsage(url)
                    for (model, counts) in usage.byModel {
                        stats.byModel[model, default: TokenCounts()].add(counts)
                        stats.totals.add(counts)
                    }
                    for (day, n) in usage.daily { stats.daily[day, default: 0] += n }
                }
            }
        }

        stats.planUsage = latestPlanUsage(dataURL.appendingPathComponent("plan-usage-history.json"))
        stats.folderBytes = folderSize(dataURL)
        return stats
    }

    // MARK: Files

    /// `<dir>/<account>/<org>/local_*.json`
    private func sessionFiles(in dir: URL) -> [URL] {
        var out: [URL] = []
        for account in children(dir) {
            for org in children(account) {
                out += children(org).filter {
                    $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json"
                }
            }
        }
        return out
    }

    /// Maps a CLI session id to its transcript plus any subagent transcripts in ~/.claude/projects.
    private func transcriptIndex() -> [String: [URL]] {
        var index: [String: [URL]] = [:]
        for project in children(Paths.claudeProjects) {
            for item in children(project) {
                if item.pathExtension == "jsonl" {
                    index[item.deletingPathExtension().lastPathComponent, default: []].append(item)
                } else if isDirectory(item) {
                    let subs = jsonlFiles(under: item)
                    if !subs.isEmpty { index[item.lastPathComponent, default: []] += subs }
                }
            }
        }
        return index
    }

    private func jsonlFiles(under dir: URL) -> [URL] {
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    private func children(_ dir: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func folderSize(_ dir: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: Parsing

    private func transcriptUsage(_ url: URL) -> TranscriptUsage {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if let (cachedAt, usage) = cache[url.path], cachedAt == mtime { return usage }

        var usage = TranscriptUsage()
        var seen = Set<String>()
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: usageNeedle) != nil {
                guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      obj["type"] as? String == "assistant",
                      let message = obj["message"] as? [String: Any],
                      let model = message["model"] as? String, model != "<synthetic>",
                      let u = message["usage"] as? [String: Any] else { continue }
                // Streaming can write the same message more than once.
                if let id = message["id"] as? String, !seen.insert(id).inserted { continue }

                var c = TokenCounts()
                c.input = u["input_tokens"] as? Int ?? 0
                c.output = u["output_tokens"] as? Int ?? 0
                c.cacheRead = u["cache_read_input_tokens"] as? Int ?? 0
                c.cacheWrite = u["cache_creation_input_tokens"] as? Int ?? 0
                c.messages = 1
                usage.byModel[model, default: TokenCounts()].add(c)

                if let ts = obj["timestamp"] as? String,
                   let date = isoFrac.date(from: ts) ?? iso.date(from: ts) {
                    usage.daily[dayFormatter.string(from: date), default: 0] += c.total
                }
            }
        }
        cache[url.path] = (mtime, usage)
        return usage
    }

    /// Claude stores periodic samples of plan usage: {"t": ms, "u": {"fh": 5-hour %, "sd": 7-day %}}.
    private func latestPlanUsage(_ url: URL) -> PlanUsage? {
        guard let samples = readJSON(url)?["samples"] as? [[String: Any]],
              let latest = samples.max(by: { ($0["t"] as? Double ?? 0) < ($1["t"] as? Double ?? 0) }),
              let t = latest["t"] as? Double,
              let u = latest["u"] as? [String: Any] else { return nil }
        return PlanUsage(fiveHour: u["fh"] as? Int, weekly: u["sd"] as? Int,
                         at: Date(timeIntervalSince1970: t / 1000))
    }
}

// MARK: Formatting

enum Fmt {
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch d {
        case 1_000_000_000...: return String(format: "%.1fB", d / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
        case 1_000...: return String(format: "%.1fK", d / 1_000)
        default: return "\(n)"
        }
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    /// "claude-opus-5-5" → "Opus 5.5", "claude-sonnet-4-5-20250929" → "Sonnet 4.5"
    static func model(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        parts.removeAll { $0.count == 8 && Int($0) != nil }
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }
}
