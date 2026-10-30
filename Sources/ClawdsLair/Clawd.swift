import AppKit
import SwiftUI

/// Clawd's animations, named the way Claude's Clawd Quest names them. Each is a pixel-art strip
/// copied out of Claude.app (see ClaudeArt).
enum ClawdAnimation: String, CaseIterable {
    case breakDancing = "BreakDancing", confetti = "Confetti", crabWalking = "CrabWalking"
    case dancingHappy = "DancingHappy", desktop = "Desktop", disappointed = "Disappointed"
    case dizzy = "Dizzy", excited = "Excited", facepalm = "Facepalm", hula = "Hula"
    case jumping = "Jumping", jumpingHappy = "JumpingHappy", laptop = "Laptop"
    case lightbulb = "Lightbulb", lookingAround = "LookingAround"
    case lookingAroundEyesOnly = "LookingAroundEyesOnly", meditating = "Meditating"
    case pointing = "Pointing", running = "Running", spark = "Spark", swaying = "Swaying"
    case thinking = "Thinking", turning = "Turning", walking = "Walking", waving = "Waving"

    /// Little things Clawd does on his own every so often.
    static let fidgets: [ClawdAnimation] = [
        .lookingAround, .lookingAroundEyesOnly, .swaying, .turning, .crabWalking, .walking,
        .meditating, .laptop, .thinking, .waving,
    ]
    /// What he might do when clicked.
    static let tricks: [ClawdAnimation] = [
        .dancingHappy, .jumpingHappy, .excited, .breakDancing, .hula, .dizzy, .spark, .confetti,
        .lightbulb, .pointing, .facepalm,
    ]
}

@MainActor
final class ClawdSprites {
    static let shared = ClawdSprites()

    struct Strip {
        let frames: [CGImage]
        let frameDuration: Duration
        let size: CGSize
        /// The bottom centre of Clawd's body, in sprite pixels from the top left. Animations
        /// have different canvas sizes, so this is what stays put when one hands over to another.
        let anchor: CGPoint
    }

    private struct Entry: Decodable {
        let width: Int
        let height: Int
        let frames: Int
        let fps: Int
        let body: [Int]
    }

    private let directory: URL? = ClaudeArt.clawd
    private lazy var manifest: [String: Entry] = {
        guard let url = directory?.appending(path: "clawd.json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }()
    private var cache: [ClawdAnimation: Strip] = [:]

    /// Clawd standing still: the first frame of his wave.
    var rest: Strip? {
        strip(.waving).map { Strip(frames: Array($0.frames.prefix(1)), frameDuration: $0.frameDuration,
                                   size: $0.size, anchor: $0.anchor) }
    }

    func strip(_ animation: ClawdAnimation) -> Strip? {
        if let cached = cache[animation] { return cached }
        guard let entry = manifest[animation.rawValue], entry.frames > 0, entry.body.count == 4,
              let url = directory?.appending(path: "\(animation.rawValue).png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let frames = (0..<entry.frames).compactMap { index in
            sheet.cropping(to: CGRect(x: 0, y: index * entry.height, width: entry.width, height: entry.height))
        }
        let body = entry.body.map(CGFloat.init)
        let strip = Strip(frames: frames, frameDuration: .milliseconds(1000 / max(entry.fps, 1)),
                          size: CGSize(width: entry.width, height: entry.height),
                          anchor: CGPoint(x: body[0] + body[2] / 2, y: body[1] + body[3]))
        cache[animation] = strip
        return strip
    }
}

/// Clawd, Claude Code's mascot, playing one of his animations in crisp pixels.
///
/// The view is the size of his body (24 × 16 sprite pixels); jumps, props and confetti spill
/// outside it, so neighbouring layout doesn't move while he plays.
struct ClawdView: View {
    /// Nil keeps him standing still.
    var animation: ClawdAnimation?
    var loops = false
    /// Points per sprite pixel.
    var scale: CGFloat = 3
    var onEnd: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame = 0

    private var playing: ClawdAnimation? { reduceMotion ? nil : animation }

    var body: some View {
        Color.clear
            .frame(width: 24 * scale, height: 16 * scale)
            .overlay(alignment: .topLeading) { sprite }
            .task(id: playing) { await play(playing) }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var sprite: some View {
        let sprites = ClawdSprites.shared
        if let strip = playing.flatMap(sprites.strip) ?? sprites.rest, !strip.frames.isEmpty {
            Image(decorative: strip.frames[min(frame, strip.frames.count - 1)], scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: strip.size.width * scale, height: strip.size.height * scale)
                .offset(x: (12 - strip.anchor.x) * scale, y: (16 - strip.anchor.y) * scale)
        } else {
            // Without Claude.app's sprites the lair from the menu bar stands in for him.
            Image(nsImage: MenuBarIcon.image)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.clay)
                .frame(width: 24 * scale, height: 16 * scale)
        }
    }

    private func play(_ animation: ClawdAnimation?) async {
        frame = 0
        guard let animation else { return }
        guard let strip = ClawdSprites.shared.strip(animation) else {
            onEnd?()
            return
        }
        repeat {
            for index in strip.frames.indices {
                frame = index
                do { try await Task.sleep(for: strip.frameDuration) } catch { return }
            }
        } while loops
        onEnd?()
    }
}

/// Clawd hanging out in the window. He fidgets every so often, does a trick when clicked, and
/// cheers (or sulks) when an account switch finishes.
struct ClawdBuddy: View {
    @EnvironmentObject var store: ProfileStore
    var scale: CGFloat = 2

    @State private var animation: ClawdAnimation? = .waving

    var body: some View {
        ClawdView(animation: animation, scale: scale) { animation = nil }
            .contentShape(Rectangle())
            .onTapGesture { animation = ClawdAnimation.tricks.filter { $0 != animation }.randomElement() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(.random(in: 9...18)))
                    if animation == nil && store.busyMessage == nil {
                        animation = ClawdAnimation.fidgets.randomElement()
                    }
                }
            }
            .onChange(of: store.busyMessage == nil) { _, idle in
                if idle { animation = store.errorMessage == nil ? .jumpingHappy : .disappointed }
            }
    }
}
