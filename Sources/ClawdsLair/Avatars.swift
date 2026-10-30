import AppKit

/// Finds an account's profile picture in Claude's own HTTP cache and keeps a copy, so it
/// survives Claude evicting it. Claude fetches it from claude.ai/api/account_avatar/<account>/…,
/// and Chromium's simple cache stores the URL in each entry's header with the body after it.
enum AccountAvatars {
    static var directory: URL { Paths.switcherDir.appendingPathComponent("Avatars") }

    static func savedURL(accountID: String) -> URL {
        directory.appendingPathComponent("\(accountID).img")
    }

    /// Returns the saved picture for this account, replacing it when Claude has cached a newer one.
    ///
    /// The saved copy's modification date is set to that of the cache entry it came from, so each
    /// refresh only has to open cache entries written since then. A changed picture gets a new URL
    /// and so a new entry, which is picked up on the next refresh.
    static func refresh(dataURL: URL, accountID: String) -> URL? {
        let fm = FileManager.default
        let saved = savedURL(accountID: accountID)
        let savedDate = (try? saved.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        if let (date, image) = newestInCache(dataURL.appendingPathComponent("Cache/Cache_Data"),
                                             accountID: accountID, after: savedDate ?? .distantPast) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if (try? image.write(to: saved, options: .atomic)) != nil {
                try? fm.setAttributes([.modificationDate: date], ofItemAtPath: saved.path)
            }
        }
        return fm.fileExists(atPath: saved.path) ? saved : nil
    }

    /// The newest cached avatar for this account among entries modified after `cutoff`.
    private static func newestInCache(_ dir: URL, accountID: String, after cutoff: Date) -> (Date, Data)? {
        let needle = Data("/api/account_avatar/\(accountID)/".utf8)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles) else { return nil }

        var best: (Date, Data)?
        for url in entries where url.lastPathComponent.hasSuffix("_0") {
            guard let date = (try? url.resourceValues(forKeys: keys))?.contentModificationDate, date > cutoff,
                  best.map({ date > $0.0 }) ?? true,
                  let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let head = (try? handle.read(upToCount: 1024)) ?? Data()
            try? handle.close()
            guard head.range(of: needle) != nil,
                  let data = try? Data(contentsOf: url),
                  let body = imageBody(in: data) else { continue }
            best = (date, body)
        }
        return best
    }

    /// Cuts the image out of a cache entry: a WebP (RIFF) container, or a PNG/JPEG run to the end.
    private static func imageBody(in data: Data) -> Data? {
        if let riff = data.range(of: Data("RIFF".utf8)), data.count >= riff.lowerBound + 8 {
            let sizeBytes = data[(riff.lowerBound + 4)..<(riff.lowerBound + 8)]
            let size = sizeBytes.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            let end = riff.lowerBound + 8 + size
            guard end <= data.count else { return nil }
            let body = data[riff.lowerBound..<end]
            return NSImage(data: body) == nil ? nil : Data(body)
        }
        for magic in [Data([0x89, 0x50, 0x4E, 0x47]), Data([0xFF, 0xD8, 0xFF])] {
            if let start = data.range(of: magic) {
                // NSImage ignores the cache's trailing metadata after the image ends.
                let body = data[start.lowerBound...]
                if NSImage(data: body) != nil { return Data(body) }
            }
        }
        return nil
    }
}

// MARK: - Palette

extension AccountAvatars {
    /// The picture's main colors, most prominent first: a few distinct, reasonably vivid
    /// shades, so a header glow made from them reads as "this picture".
    static func palette(of image: NSImage, count: Int = 4) -> [NSColor] {
        let side = 24
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Bucket by hue, saturation and brightness, keeping each bucket's average color.
        struct Bucket { var r = 0.0, g = 0.0, b = 0.0, n = 0.0 }
        var buckets: [Int: Bucket] = [:]
        for i in 0..<(side * side) {
            let p = pixels + i * 4
            guard p[3] > 128 else { continue }
            let color = NSColor(srgbRed: CGFloat(p[0]) / 255, green: CGFloat(p[1]) / 255, blue: CGFloat(p[2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
            // Greys share one hue bucket so they don't split across hues.
            let hueKey = s < 0.15 ? 12 : Int(h * 12) % 12
            let key = hueKey * 100 + min(Int(s * 3), 2) * 10 + min(Int(v * 3), 2)
            buckets[key, default: Bucket()].r += Double(p[0])
            buckets[key, default: Bucket()].g += Double(p[1])
            buckets[key, default: Bucket()].b += Double(p[2])
            buckets[key, default: Bucket()].n += 1
        }

        let candidates: [(color: NSColor, score: Double)] = buckets.values.map { bucket in
            let color = NSColor(srgbRed: bucket.r / bucket.n / 255, green: bucket.g / bucket.n / 255,
                                blue: bucket.b / bucket.n / 255, alpha: 1)
            var s: CGFloat = 0, v: CGFloat = 0
            color.getHue(nil, saturation: &s, brightness: &v, alpha: nil)
            // Area matters most, but a vivid patch beats a big murky one.
            return (color, bucket.n * (0.35 + Double(s)) * (0.25 + Double(v)))
        }
        .sorted { $0.score > $1.score }

        var picked: [NSColor] = []
        for candidate in candidates where picked.count < count {
            if picked.allSatisfy({ distance($0, candidate.color) > 0.18 }) { picked.append(candidate.color) }
        }
        return picked.map(lifted)
    }

    private static func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let dr = a.redComponent - b.redComponent, dg = a.greenComponent - b.greenComponent
        let db = a.blueComponent - b.blueComponent
        return sqrt(dr * dr + dg * dg + db * db)
    }

    /// Keeps the glow a quiet tint behind the header: very dark photos are lifted just
    /// enough to show, and bright ones are pulled down so they never glare.
    private static func lifted(_ color: NSColor) -> NSColor {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
        return NSColor(hue: h, saturation: min(1, s * 0.9), brightness: min(max(v, 0.28), 0.52), alpha: 1)
    }
}
