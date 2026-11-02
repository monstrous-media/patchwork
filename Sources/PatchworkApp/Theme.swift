#if os(macOS)
import SwiftUI
import AppKit

/// Patchwork's look: a matte-black panel, cream text and one signal colour — the yellow-green of the
/// M1's backlit LCD — used wherever a value or state means "what the synth will receive / has confirmed".
/// Amber means the screen is ahead of the synth; red is reserved for refusals in the log.
///
/// Every role has a light variant with the same meaning. To try another accent, change `accent` only.
enum Theme {
    // Surfaces (dark / light)
    static let window  = Color(light: "F3F2EE", dark: "0F1114")   // behind everything
    static let surface = Color(light: "F7F6F3", dark: "15171C")   // content area, MIDI bar
    static let raised  = Color(light: "FFFFFF", dark: "1B1E24")   // toolbar strips, sections, play bar
    static let sidebar = Color(light: "EDEBE6", dark: "121418")
    static let control = Color(light: "E7E5DF", dark: "262A32")   // chips, selected nav
    static let line    = Color(light: "D8D6D0", dark: "2A2E36")   // hairlines, section borders
    static let well    = Color(light: "ECEAE4", dark: "0B0D10")   // LCD-style fields: name, envelopes, log

    // Text
    static let text    = Color(light: "1B1E24", dark: "E6E4DF")
    static let muted   = Color(light: "5B6068", dark: "A3A8B1")
    static let faint   = Color(light: "767B84", dark: "8A9099")
    static let wellText = Color(light: "1B1E24", dark: "D9D6CF")

    // Signal colours
    static let accent    = Color(light: "4C8A12", dark: "B8F06A")
    static let accentInk = Color(light: "FFFFFF", dark: "0F1A05") // text on accent
    static let wellAccent = Color(light: "4C8A12", dark: "B8F06A") // accent inside a well

    // Keyboard: ivory and ebony whatever the appearance
    static let keyWhite = Color(light: "FFFFFF", dark: "E6E4DF")
    static let keyBlack = Color(light: "1B1E24", dark: "0F1114")
    static let keyLine  = Color(light: "C9C7C1", dark: "0F1114")
    static let amber     = Color(light: "A8641A", dark: "F2B45A")
    static let red       = Color(light: "C23B3B", dark: "F06B6B")
    static let blue      = Color(light: "1F7E9C", dark: "7FD7F0")

    // Shape
    static let controlRadius: CGFloat = 7
    static let sectionRadius: CGFloat = 12

    // Type. SF stands in for the display/mono faces on the token sheet, so nothing is bundled.
    static let sectionTitle = Font.system(size: 13, weight: .bold)
    static let groupHeader = Font.system(size: 10.5, weight: .medium, design: .monospaced)
    static let value = Font.system(size: 12.5, weight: .medium, design: .monospaced)
    static let lcd = Font.system(size: 20, weight: .medium, design: .monospaced)
    static let mono = Font.system(.body, design: .monospaced)
    static let monoCaption = Font.system(size: 11.5, design: .monospaced)
}

extension Color {
    /// A colour that follows the window's appearance.
    init(light: String, dark: String) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

/// Small uppercase monospaced heading for a group of things (sidebar groups, field captions).
struct GroupHeader: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(Theme.groupHeader).tracking(1).foregroundStyle(Theme.faint)
    }
}

/// Status pill: "edited · auto-sent", "as received" …
struct StatusChip: View {
    enum Tone { case neutral, good, warn }
    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(fill))
            .foregroundStyle(fg)
    }
    private var fill: Color {
        switch tone { case .neutral: return Theme.control; case .good: return Theme.accent.opacity(0.18); case .warn: return Theme.amber.opacity(0.18) }
    }
    private var fg: Color {
        switch tone { case .neutral: return Theme.text; case .good: return Theme.accent; case .warn: return Theme.amber }
    }
}

/// A themed section: display-face title, optional caption on the right, raised ground with a hairline.
struct SectionCard<Content: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Theme.sectionTitle).tracking(0.3).foregroundStyle(Theme.text)
                Spacer()
                if let c = caption { Text(c).font(Theme.groupHeader).foregroundStyle(Theme.faint) }
            }
            content()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Theme.sectionRadius).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: Theme.sectionRadius).stroke(Theme.line, lineWidth: 1))
    }
}

/// Appearance preference: dark is the default; View ▸ Appearance switches.
enum Appearance: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Applied app-wide through AppKit: SwiftUI's preferredColorScheme(nil) does not revert to the
    /// system setting once a scheme has been forced, but NSApp.appearance = nil does.
    func apply() {
        switch self {
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .system: NSApp.appearance = nil
        }
    }
}
#endif
