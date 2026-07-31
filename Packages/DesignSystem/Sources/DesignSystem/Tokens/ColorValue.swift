import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Straight sRGB color components parsed from a hex string.
///
/// Internal on purpose: raw color math lives only inside the token layer. Features
/// consume semantic `WatakeColor` values, never `RGBA`.
struct RGBA: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    /// Parses `#RRGGBB` or `#RRGGBBAA` (leading `#` optional). Returns `nil` on
    /// any malformed input so token typos fail loudly in tests.
    init?(hex: String) {
        var string = hex
        if string.hasPrefix("#") {
            string.removeFirst()
        }
        let isValidLength = string.count == 6 || string.count == 8
        guard isValidLength, let value = UInt64(string, radix: 16) else {
            return nil
        }
        if string.count == 6 {
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
            alpha = 1
        } else {
            red = Double((value & 0xFF00_0000) >> 24) / 255
            green = Double((value & 0x00FF_0000) >> 16) / 255
            blue = Double((value & 0x0000_FF00) >> 8) / 255
            alpha = Double(value & 0x0000_00FF) / 255
        }
    }
}

extension RGBA {
    /// WCAG 2.x relative luminance of the (opaque) color.
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2.x contrast ratio (1...21) against another opaque color.
    func contrastRatio(against other: RGBA) -> Double {
        let lhs = relativeLuminance
        let rhs = other.relativeLuminance
        let lighter = max(lhs, rhs)
        let darker = min(lhs, rhs)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Source-over composite of `self` (using `alpha`) atop an opaque background.
    func composited(over background: RGBA) -> RGBA {
        func blend(_ top: Double, _ bottom: Double) -> Double {
            top * alpha + bottom * (1 - alpha)
        }
        return RGBA(
            red: blend(red, background.red),
            green: blend(green, background.green),
            blue: blend(blue, background.blue),
            alpha: 1
        )
    }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// A semantic color defined by its light- and dark-appearance components.
///
/// Resolves to a dynamic platform color so a single token tracks the system
/// appearance. Document, photo, and watermark content must never be routed
/// through these tokens — see `WatakeColor` documentation.
struct ColorValue {
    let light: RGBA
    let dark: RGBA

    /// Fails fast during development if a token hex is malformed.
    init(lightHex: String, darkHex: String) {
        guard let light = RGBA(hex: lightHex), let dark = RGBA(hex: darkHex) else {
            preconditionFailure("Invalid design-token hex: \(lightHex) / \(darkHex)")
        }
        self.light = light
        self.dark = dark
    }

    var color: Color {
        Color(light: light, dark: dark)
    }
}

extension Color {
    /// Builds an appearance-reactive color from explicit light/dark components.
    init(light: RGBA, dark: RGBA) {
        #if canImport(UIKit)
            self.init(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark.platformColor : light.platformColor
            })
        #elseif canImport(AppKit)
            self.init(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return (isDark ? dark : light).platformColor
            })
        #else
            self.init(.sRGB, red: light.red, green: light.green, blue: light.blue, opacity: light.alpha)
        #endif
    }
}

extension RGBA {
    #if canImport(UIKit)
        var platformColor: UIColor {
            UIColor(red: red, green: green, blue: blue, alpha: alpha)
        }
    #elseif canImport(AppKit)
        var platformColor: NSColor {
            NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        }
    #endif
}
