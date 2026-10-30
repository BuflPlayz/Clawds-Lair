import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Claude's spark and Clawd animations, copied out of the installed Claude.app the first time
/// the app runs and again whenever Claude updates, so none of Claude's artwork ships with this app.
///
/// Spark: the sprites live inside Claude's web bundle (ion-dist.asar) as vertical SVG strips,
/// one frame per cell. Each becomes Sparks/<state>.svg next to a sparks.json manifest that
/// SparkSprites reads.
///
/// Clawd: Claude's Clawd Quest game (app.asar) carries Clawd's pixel-art animations as a palette
/// plus per-frame pixel deltas. Each becomes Clawd/<name>.png, a vertical strip with one frame
/// per cell, next to a clawd.json manifest that ClawdSprites reads.
///
/// Without Claude.app, or if a Claude update moves things around, the views fall back to a
/// system icon and a still silhouette.
enum ClaudeArt {
    static var directory: URL { Paths.switcherDir.appendingPathComponent("ClaudeArt") }
    static var sparks: URL { directory.appendingPathComponent("Sparks") }
    static var clawd: URL { directory.appendingPathComponent("Clawd") }
    private static var stamp: URL { directory.appendingPathComponent("claude-version") }

    /// Copies the art if Claude's version has changed since the last copy. Takes well under a
    /// second, so it runs before any view asks for a sprite.
    static func prepare() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ClaudeLauncher.bundleID) else { return }
        let version = Bundle(url: app)?.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        if (try? String(contentsOf: stamp, encoding: .utf8)) == version { return }

        let fm = FileManager.default
        let staging = Paths.switcherDir.appendingPathComponent("ClaudeArt-new")
        try? fm.removeItem(at: staging)
        let resources = app.appending(path: "Contents/Resources")
        extractSparks(from: resources.appending(path: "ion-dist.asar"), to: staging.appendingPathComponent("Sparks"))
        extractClawd(from: resources.appending(path: "app.asar"), to: staging.appendingPathComponent("Clawd"))
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try version.write(to: staging.appendingPathComponent("claude-version"), atomically: true, encoding: .utf8)
            try? fm.removeItem(at: directory)
            try fm.moveItem(at: staging, to: directory)
        } catch {
            NSLog("Couldn't save Claude's artwork: \(error)")
        }
    }

    // MARK: - asar

    /// Calls `body` with every packed .js file in an asar archive until it returns true.
    private static func eachScript(in archive: URL, _ body: (Data) -> Bool) {
        guard let file = try? FileHandle(forReadingFrom: archive) else { return }
        defer { try? file.close() }
        func uint32(_ data: Data, at offset: Int) -> Int {
            data.subdata(in: offset..<offset + 4).withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        }
        guard let prefix = try? file.read(upToCount: 8), prefix.count == 8 else { return }
        let headerSize = uint32(prefix, at: 4)
        guard let header = try? file.read(upToCount: headerSize), header.count == headerSize else { return }
        let jsonLength = uint32(header, at: 4)
        guard 8 + jsonLength <= header.count,
              let tree = try? JSONSerialization.jsonObject(with: header.subdata(in: 8..<8 + jsonLength)) as? [String: Any]
        else { return }
        let base = UInt64(8 + headerSize)

        var entries: [[String: Any]] = []
        func walk(_ node: [String: Any]) {
            for (name, child) in node["files"] as? [String: Any] ?? [:] {
                guard let child = child as? [String: Any] else { continue }
                if child["files"] != nil {
                    walk(child)
                } else if name.hasSuffix(".js"), child["unpacked"] as? Bool != true {
                    entries.append(child)
                }
            }
        }
        walk(tree)

        for entry in entries {
            guard let offset = (entry["offset"] as? String).flatMap(UInt64.init),
                  let size = entry["size"] as? Int,
                  (try? file.seek(toOffset: base + offset)) != nil,
                  let data = try? file.read(upToCount: size) else { continue }
            if body(data) { return }
        }
    }

    // MARK: - Spark

    private static let sparkEntry = try! NSRegularExpression(
        pattern: #"([\w-]+|"[\w-]+"):\{svg:'(<svg[^']*</svg>)',width:(\d+),height:(\d+),frameCount:(\d+),speed:(\d+)\}"#)

    private static func extractSparks(from archive: URL, to out: URL) {
        var manifest: [String: [String: Int]] = [:]
        eachScript(in: archive) { data in
            guard data.range(of: Data("as animations}".utf8)) != nil,
                  data.range(of: Data("tickle:{svg:".utf8)) != nil else { return false }
            let source = String(decoding: data, as: UTF8.self)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            for match in sparkEntry.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                func group(_ i: Int) -> String { Range(match.range(at: i), in: source).map { String(source[$0]) } ?? "" }
                let state = group(1).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                // The web app fills with currentColor via CSS; give the file a solid fill so it
                // can be used as a template image and tinted in SwiftUI.
                var svg = group(2)
                if let tag = svg.range(of: "<svg ") {
                    svg.replaceSubrange(tag, with: ##"<svg xmlns="http://www.w3.org/2000/svg" fill="#000" "##)
                }
                try? svg.write(to: out.appendingPathComponent("\(state).svg"), atomically: true, encoding: .utf8)
                manifest[state] = ["frames": Int(group(5)) ?? 0, "speed": Int(group(6)) ?? 0]
            }
            return true
        }
        guard !manifest.isEmpty, let json = try? JSONSerialization.data(withJSONObject: manifest) else {
            NSLog("Claude's spark animations weren't found; using a static icon")
            return
        }
        try? json.write(to: out.appendingPathComponent("sparks.json"))
    }

    // MARK: - Clawd

    /// The start of Clawd's sprite table, e.g. `te={BreakDancing:{cat:"Core",...`.
    private static let clawdTable = try! NSRegularExpression(pattern: #"\w+=\{\w+:\{cat:""#)
    /// The minifier writes some lists as "a(b(c".split("(").
    private static let splitList = try! NSRegularExpression(pattern: #""([^"]*)"\.split\("(.)"\)"#)
    private static let bareKey = try! NSRegularExpression(pattern: #"([{,])([A-Za-z_]\w*):"#)

    /// Parses the minified sprite table literal, or nil if it isn't there.
    private static func spriteTable(in source: String) -> [String: [String: Any]]? {
        let ns = source as NSString
        guard let match = clawdTable.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let start = ns.range(of: "{", range: NSRange(location: match.range.location, length: match.range.length)).location
        var depth = 0
        var end = start
        let brace = UInt16(UInt8(ascii: "{")), close = UInt16(UInt8(ascii: "}"))
        while end < ns.length {
            let c = ns.character(at: end)
            if c == brace { depth += 1 } else if c == close { depth -= 1; if depth == 0 { break } }
            end += 1
        }
        guard depth == 0 else { return nil }
        let literal = NSMutableString(string: ns.substring(with: NSRange(location: start, length: end - start + 1)))
        for m in splitList.matches(in: literal as String, range: NSRange(location: 0, length: literal.length)).reversed() {
            let items = literal.substring(with: m.range(at: 1)).components(separatedBy: literal.substring(with: m.range(at: 2)))
            guard let json = try? JSONSerialization.data(withJSONObject: items) else { return nil }
            literal.replaceCharacters(in: m.range, with: String(decoding: json, as: UTF8.self))
        }
        bareKey.replaceMatches(in: literal, range: NSRange(location: 0, length: literal.length), withTemplate: "$1\"$2\":")
        return try? JSONSerialization.jsonObject(with: Data((literal as String).utf8)) as? [String: [String: Any]]
    }

    /// Decodes a sprite's base frame and deltas into one list of palette indices per frame.
    ///
    /// Each pixel is a base-36 palette index, or "." for transparent. A delta lists the pixels
    /// that change from the previous frame as <base-36 position><new value>.
    private static func frames(base: String, deltas: [Any]) -> [[Int?]] {
        func value(_ c: Character) -> Int? { c == "." ? nil : Int(String(c), radix: 36) }
        var pixels = base.map(value)
        var frames = [pixels]
        for delta in deltas {
            for change in (delta as? String ?? "").split(separator: ",") {
                guard let position = Int(change.dropLast(), radix: 36), pixels.indices.contains(position) else { continue }
                pixels[position] = value(change.last!)
            }
            frames.append(pixels)
        }
        return frames
    }

    private static func extractClawd(from archive: URL, to out: URL) {
        var table: [String: [String: Any]]?
        eachScript(in: archive) { data in
            guard data.range(of: Data("clawd-quest: no sprite data".utf8)) != nil else { return false }
            table = spriteTable(in: String(decoding: data, as: UTF8.self))
            return true
        }
        guard let table else {
            NSLog("Clawd's animations weren't found; he'll stand still")
            return
        }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var manifest: [String: [String: Any]] = [:]
        for (name, sprite) in table {
            guard let w = sprite["w"] as? Int, let h = sprite["h"] as? Int, w > 0, h > 0,
                  let palette = sprite["palette"] as? [String], let base = sprite["base"] as? String,
                  let fps = sprite["fps"] as? Int, let body = sprite["a0"] as? [Int] else { continue }
            let colors = palette.map { hex -> [UInt8] in
                let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
                return [UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff), 255]
            }
            let all = frames(base: base, deltas: sprite["deltas"] as? [Any] ?? [])
            var rgba = [UInt8]()
            rgba.reserveCapacity(w * h * all.count * 4)
            for frame in all {
                for index in 0..<w * h {
                    let p = index < frame.count ? frame[index] : nil
                    rgba += p.flatMap { colors.indices.contains($0) ? colors[$0] : nil } ?? [0, 0, 0, 0]
                }
            }
            guard writePNG(rgba, width: w, height: h * all.count, to: out.appendingPathComponent("\(name).png")) else { continue }
            // a0 is the box around Clawd's body in the first frame; the view pins it in place so
            // he doesn't shift between animations of different sizes.
            manifest[name] = ["width": w, "height": h, "frames": all.count, "fps": fps, "body": body]
        }
        if let json = try? JSONSerialization.data(withJSONObject: manifest) {
            try? json.write(to: out.appendingPathComponent("clawd.json"))
        }
    }

    private static func writePNG(_ rgba: [UInt8], width: Int, height: Int, to url: URL) -> Bool {
        // Pixels are either fully opaque or fully clear, so premultiplied is the same data.
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
