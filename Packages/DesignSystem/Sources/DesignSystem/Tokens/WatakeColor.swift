import SwiftUI

// Lowercase nested enums are intentional semantic namespaces (WatakeColor.brand.primary).
// swiftlint:disable type_name

/// Semantic color tokens for Watake. Values come from `Design.md` and are the
/// only place raw hex is permitted.
///
/// Rules:
/// - Components use these tokens; never raw `Color(red:)`, hex, or `Color.blue`.
/// - Never route document images, photographs, imported logos, or rendered
///   watermarks through these tokens. Document content keeps its own colors and
///   is never inverted for Dark mode.
public enum WatakeColor {
    /// Brand action colors (filled primary buttons, selection accents).
    public enum brand {
        public static let primary = ColorValue(lightHex: "#1F4FEB", darkHex: "#4C7BFF").color
        public static let primaryPressed = ColorValue(lightHex: "#1841C7", darkHex: "#6B92FF").color
        public static let primaryDisabled = ColorValue(lightHex: "#AAB9F7", darkHex: "#26355F").color
    }

    /// Layered background surfaces (base canvas, raised cards, sunken wells).
    public enum surface {
        public static let base = ColorValue(lightHex: "#FFFFFF", darkHex: "#0B0F1A").color
        public static let raised = ColorValue(lightHex: "#F6F7FB", darkHex: "#141A2A").color
        public static let sunken = ColorValue(lightHex: "#EEF0F6", darkHex: "#0A0E18").color
    }

    /// Hairline separators. Prefer borders over heavy shadows in Dark mode.
    public enum border {
        public static let subtle = ColorValue(lightHex: "#E5E7EB", darkHex: "#273044").color
        public static let strong = ColorValue(lightHex: "#CBD1DC", darkHex: "#566078").color
    }

    /// Foreground text and glyph colors, including on-fill variants.
    public enum text {
        public static let primary = ColorValue(lightHex: "#0B1220", darkHex: "#F5F7FB").color
        public static let secondary = ColorValue(lightHex: "#5B6474", darkHex: "#A2ACBD").color
        public static let disabled = ColorValue(lightHex: "#9AA3B2", darkHex: "#6A7386").color
        public static let onPrimary = ColorValue(lightHex: "#FFFFFF", darkHex: "#0B1220").color
        public static let onWarning = ColorValue(lightHex: "#0B1220", darkHex: "#0B1220").color
        public static let onDanger = ColorValue(lightHex: "#FFFFFF", darkHex: "#0B1220").color
    }

    /// Status / accent colors for warnings, success, and destructive actions.
    public enum status {
        public static let warning = ColorValue(lightHex: "#F59E0B", darkHex: "#FBBF24").color
        public static let success = ColorValue(lightHex: "#047857", darkHex: "#34D399").color
        public static let danger = ColorValue(lightHex: "#B91C1C", darkHex: "#F87171").color
    }

    /// Dimming overlay behind modals and sheets. Already includes its own alpha.
    public static let scrim = ColorValue(lightHex: "#0B122066", darkHex: "#00000099").color
}

// swiftlint:enable type_name
