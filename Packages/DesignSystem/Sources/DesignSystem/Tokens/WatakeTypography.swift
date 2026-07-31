import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Semantic type styles from `Design.md`.
///
/// Each style keeps the design's base point size but scales with Dynamic Type
/// through `UIFontMetrics`, anchored to the nearest system text style. There are
/// no fixed, viewport-scaled fonts — size responds to the user's content-size
/// preference, not the screen width.
///
/// Apply with `.watakeType(_:)` so per-style extras (overline uppercasing and
/// tracking) are handled consistently.
public enum WatakeTypography: CaseIterable {
    case display
    case title1
    case title2
    case body
    case bodyEmphasis
    case caption
    case overline
    case mono

    /// Base point size at the default (Large) content size.
    var size: CGFloat {
        switch self {
        case .display: 32
        case .title1: 24
        case .title2: 20
        case .body, .bodyEmphasis: 16
        case .caption: 13
        case .overline: 11
        case .mono: 14
        }
    }

    /// Target line height from `Design.md`, at the default content size.
    var lineHeight: CGFloat {
        switch self {
        case .display: 40
        case .title1: 32
        case .title2: 28
        case .body, .bodyEmphasis: 24
        case .caption: 18
        case .overline: 16
        case .mono: 20
        }
    }

    /// Extra leading (line height minus font size) at the default content size.
    /// SwiftUI's `lineSpacing` adds this between lines.
    var lineSpacing: CGFloat {
        max(0, lineHeight - size)
    }

    /// `lineSpacing` scaled for the current Dynamic Type content size so the
    /// leading tracks the font, matching the `UIFontMetrics`-scaled point size.
    var scaledLineSpacing: CGFloat {
        #if canImport(UIKit)
            return UIFontMetrics(forTextStyle: uiTextStyle).scaledValue(for: lineSpacing)
        #else
            return lineSpacing
        #endif
    }

    var weight: Font.Weight {
        switch self {
        case .display, .title1: .bold
        case .title2, .bodyEmphasis, .overline: .semibold
        case .body, .caption, .mono: .regular
        }
    }

    var design: Font.Design {
        self == .mono ? .monospaced : .default
    }

    /// Extra letter spacing (overline only, per `Design.md`).
    var tracking: CGFloat {
        self == .overline ? 0.55 : 0
    }

    /// Overline is rendered uppercase.
    var textCase: Text.Case? {
        self == .overline ? .uppercase : nil
    }

    #if canImport(UIKit)
        /// System text style used to drive the Dynamic Type scaling curve.
        private var uiTextStyle: UIFont.TextStyle {
            switch self {
            case .display: .largeTitle
            case .title1: .title1
            case .title2: .title2
            case .body, .bodyEmphasis, .mono: .body
            case .caption: .footnote
            case .overline: .caption2
            }
        }

        private var uiWeight: UIFont.Weight {
            switch weight {
            case .bold: .bold
            case .semibold: .semibold
            default: .regular
            }
        }
    #endif

    /// Dynamic Type-aware font for this style.
    public var font: Font {
        #if canImport(UIKit)
            let base: UIFont = design == .monospaced
                ? .monospacedSystemFont(ofSize: size, weight: uiWeight)
                : .systemFont(ofSize: size, weight: uiWeight)
            let scaled = UIFontMetrics(forTextStyle: uiTextStyle).scaledFont(for: base)
            return Font(scaled)
        #else
            return .system(size: size, weight: weight, design: design)
        #endif
    }
}

extension View {
    /// Applies a semantic Watake type style, including overline case and tracking.
    public func watakeType(_ style: WatakeTypography) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .textCase(style.textCase)
            .lineSpacing(style.scaledLineSpacing)
    }
}

extension Text {
    /// Convenience for `Text` so overline case/tracking apply without a wrapper.
    public func watakeType(_ style: WatakeTypography) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .textCase(style.textCase)
            .lineSpacing(style.scaledLineSpacing)
    }
}
