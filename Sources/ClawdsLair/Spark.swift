import AppKit
import SwiftUI

/// The animations Claude plays on its spark. Each is a sprite strip copied out of Claude.app
/// (see ClaudeArt).
enum SparkState: String {
    case idle, entrance, exit, tickle, thinking, writing, waiting, shimmer, orbiting

    /// One-shot animations play once and call `onEnd`; the rest loop until the state changes.
    var loops: Bool { ![.entrance, .exit, .tickle].contains(self) }
}

@MainActor
final class SparkSprites {
    static let shared = SparkSprites()

    struct Strip {
        let frames: [NSImage]
        let frameDuration: Duration
    }

    private struct Entry: Decodable {
        let frames: Int
        let speed: Int
    }

    private let directory: URL? = ClaudeArt.sparks
    private lazy var manifest: [String: Entry] = {
        guard let url = directory?.appending(path: "sparks.json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }()
    private var cache: [SparkState: Strip] = [:]

    /// The resting spark: the first frame of the tickle strip.
    var rest: NSImage? { strip(.tickle)?.frames.first }

    func strip(_ state: SparkState) -> Strip? {
        if let cached = cache[state] { return cached }
        guard let entry = manifest[state.rawValue], entry.frames > 0,
              let url = directory?.appending(path: "\(state.rawValue).svg"),
              let sheet = NSImage(contentsOf: url) else { return nil }
        let full = sheet.size
        let cell = NSSize(width: full.width, height: full.height / CGFloat(entry.frames))
        let frames = (0..<entry.frames).map { index in
            let frame = NSImage(size: cell, flipped: true) { _ in
                sheet.draw(in: NSRect(x: 0, y: -CGFloat(index) * cell.height, width: full.width, height: full.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                return true
            }
            frame.isTemplate = true
            return frame
        }
        let strip = Strip(frames: frames, frameDuration: .milliseconds(entry.speed))
        cache[state] = strip
        return strip
    }
}

/// Claude's spark mark, animated the way Claude animates it.
struct SparkView: View {
    var state: SparkState = .idle
    var size: CGFloat = 32
    var color: Color = .clay
    /// Plays the "tickle" wiggle when clicked while idle, like the spark in Claude.
    var ticklesOnTap = false
    var onEnd: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame = 0
    @State private var tickling = false

    private var playing: SparkState {
        if reduceMotion { return .idle }
        return tickling ? .tickle : state
    }

    var body: some View {
        mark
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .onTapGesture {
                if ticklesOnTap && state == .idle && !tickling { tickling = true }
            }
            .task(id: playing) { await play(playing) }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        let sprites = SparkSprites.shared
        let image = playing == .idle ? sprites.rest : sprites.strip(playing)?.frames[safe: frame] ?? sprites.rest
        if let image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .foregroundStyle(color)
        } else {
            Image(systemName: "asterisk")
                .resizable()
                .scaledToFit()
                .fontWeight(.bold)
                .foregroundStyle(color)
                .padding(size * 0.12)
        }
    }

    private func play(_ state: SparkState) async {
        frame = 0
        guard state != .idle, let strip = SparkSprites.shared.strip(state) else {
            if state != .idle { finish() }
            return
        }
        repeat {
            for index in strip.frames.indices {
                frame = index
                do { try await Task.sleep(for: strip.frameDuration) } catch { return }
            }
        } while state.loops
        finish()
    }

    private func finish() {
        if tickling {
            tickling = false
        } else {
            onEnd?()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
