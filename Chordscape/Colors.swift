import SwiftUI

/// Chordscape's palette — a cream, pastel "instrument in a box" look (own take on
/// the chord-synth genre, not a copy of any single product's specific hues).
/// Every color is dynamic (`Color.dynamic(light:dark:)`, see below) so the
/// dark-mode toggle needed zero changes at any of the ~10 call sites that
/// already reference `Color.chordscapeXxx` — only this file changed.
extension Color {
    static let chordscapeBackground = Color.dynamic(light: 0xF7EFE3, dark: 0x1C1815)
    static let chordscapePanel = Color.dynamic(light: 0xFFF9F1, dark: 0x2A2420)
    static let chordscapeInk = Color.dynamic(light: 0x3A2E28, dark: 0xF0E6D8)

    static let chordscapeCoral = Color.dynamic(light: 0xE8836B, dark: 0xF0967E)
    static let chordscapeGold = Color.dynamic(light: 0xE0A84F, dark: 0xF0BE6E)
    static let chordscapeMoss = Color.dynamic(light: 0x8FA663, dark: 0xA4C17F)
    static let chordscapeMint = Color.dynamic(light: 0x6FB79A, dark: 0x86D2B3)
    static let chordscapeSky = Color.dynamic(light: 0x7AA6C2, dark: 0x92C2DE)
    static let chordscapeLavender = Color.dynamic(light: 0xA695C7, dark: 0xC0AAE6)
    static let chordscapeBlush = Color.dynamic(light: 0xE4A6B8, dark: 0xF2BBCC)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// Resolves to `dark` or `light` hex automatically based on the current
    /// trait collection — i.e. whatever `.preferredColorScheme` is in
    /// effect for the view hierarchy this color is drawn in. Bridges
    /// through `UIColor { traits in ... }` since plain SwiftUI `Color`
    /// values have no built-in way to vary by appearance without an asset
    /// catalog color set.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
