import AppKit
import CoreText
import SwiftUI

// MARK: - Colors

/// Claude's palette: warm off-black and paper backgrounds with the clay accent.
extension Color {
    static let clay = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    static let canvas = Color(light: 0xFAF9F5, dark: 0x262624)
    static let surface = Color(light: 0xFFFFFF, dark: 0x30302E)
    static let hairline = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(hex: 0xDEDCD1, alpha: 0.14) : NSColor(hex: 0x1F1E1D, alpha: 0.12)
    })
    static let textSecondary = Color(light: 0x3D3D3A, dark: 0xC2C0B6)
    static let textTertiary = Color(light: 0x73726C, dark: 0x9C9A92)

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: dark) : NSColor(hex: light) })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

// MARK: - Fonts

/// Anthropic Sans and Serif, loaded straight from the installed Claude.app so nothing is
/// bundled. Falls back to the system fonts if Claude isn't installed.
enum ClaudeFonts {
    private(set) static var available = false

    static func register() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ClaudeLauncher.bundleID) else { return }
        let dir = app.appending(path: "Contents/Resources/fonts")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        available = NSFont(name: "AnthropicSansVariable-TextRegular", size: 12) != nil
    }

    static func name(_ family: String, _ size: CGFloat, _ weight: Font.Weight) -> String {
        let optical = size >= 20 ? "Display" : "Text"
        let w: String = switch weight {
        case .light, .thin, .ultraLight: "Light"
        case .medium: "Medium"
        case .semibold: "Semibold"
        case .bold: "Bold"
        case .heavy, .black: "Extrabold"
        default: "Regular"
        }
        return "Anthropic\(family)Variable-\(optical)\(w)"
    }
}

extension Font {
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        ClaudeFonts.available
            ? .custom(ClaudeFonts.name("Sans", size, weight), fixedSize: size)
            : .system(size: size, weight: weight)
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        ClaudeFonts.available
            ? .custom(ClaudeFonts.name("Serif", size, weight), fixedSize: size)
            : .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Menu bar icon

enum MenuBarIcon {
    /// The lair: a rock with a cave in it and two eyes looking out, as a template image.
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 1, y: 15))
            path.curve(to: NSPoint(x: 10, y: 1), controlPoint1: NSPoint(x: 1.5, y: 8), controlPoint2: NSPoint(x: 5.5, y: 1))
            path.curve(to: NSPoint(x: 19, y: 15), controlPoint1: NSPoint(x: 14.5, y: 1), controlPoint2: NSPoint(x: 18.5, y: 8))
            path.close()
            // The cave is a hole in the rock, and the eyes are filled again inside it.
            path.move(to: NSPoint(x: 6, y: 15))
            path.line(to: NSPoint(x: 6, y: 10))
            path.curve(to: NSPoint(x: 14, y: 10), controlPoint1: NSPoint(x: 6, y: 5.5), controlPoint2: NSPoint(x: 14, y: 5.5))
            path.line(to: NSPoint(x: 14, y: 15))
            path.close()
            path.appendRect(NSRect(x: 7.5, y: 9.5, width: 1.5, height: 2.5))
            path.appendRect(NSRect(x: 11, y: 9.5, width: 1.5, height: 2.5))
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

// MARK: - Surfaces

extension View {
    /// A Liquid Glass panel, optionally washed with a color.
    func glassCard(cornerRadius: CGFloat = 24, tint: Color? = nil) -> some View {
        glassEffect(tint.map { Glass.regular.tint($0.opacity(0.14)) } ?? .regular,
                    in: .rect(cornerRadius: cornerRadius))
    }

    /// The faint inset fill Claude uses for tiles inside a card.
    func insetFill(cornerRadius: CGFloat = 14) -> some View {
        background(Color.primary.opacity(0.045), in: .rect(cornerRadius: cornerRadius))
    }
}

/// Small section label, like "Recent artifacts" on Claude's home screen.
struct SectionLabel: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text).font(.sans(14, .medium)).foregroundStyle(Color.textSecondary)
            Spacer()
            if let trailing {
                Text(trailing).font(.sans(13)).foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Rounded capsule meter used for plan usage and model share.
struct Meter: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(6, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.smooth, value: fraction)
    }
}

/// A small tinted capsule label, optionally with a pulsing "live" dot.
struct Badge: View {
    let text: String
    let color: Color
    var live = false

    var body: some View {
        HStack(spacing: 4) {
            if live {
                Circle().fill(color).frame(width: 5, height: 5)
                    .phaseAnimator([1.0, 0.35]) { $0.opacity($1) } animation: { _ in .easeInOut(duration: 1.1) }
            }
            Text(text).font(.sans(10, .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.16)))
        .foregroundStyle(color)
    }
}

/// A glass capsule toggle that fills with a color when selected.
struct GlassChip<Label: View>: View {
    let selected: Bool
    let tint: Color
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(tint).interactive() : .regular.interactive(), in: .capsule)
    }
}
