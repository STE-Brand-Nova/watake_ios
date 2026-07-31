import CoreGraphics

/// Width class derived from a container's available width, per `RESPONSIVE.md`.
///
/// This is a decision helper only. Features still lay themselves out with
/// `GeometryReader`, `ViewThatFits`, adaptive grids, and `NavigationSplitView`.
/// Never branch on device model or `UIScreen.main.bounds`.
public enum WatakeWidthClass: Equatable {
    /// `< 700pt` — one column; iPhone navigation and bottom tab bar.
    case compact
    /// `700...1099pt` — two columns where useful; iPad sidebar.
    case regular
    /// `>= 1100pt` — up to three columns; two-pane editors.
    case expanded
}

/// Layout decisions based on the available container width.
public enum WatakeLayout {
    /// Regular-class lower bound.
    public static let regularBreakpoint: CGFloat = 700
    /// Expanded-class lower bound.
    public static let expandedBreakpoint: CGFloat = 1100

    /// Classifies a container width into a `WatakeWidthClass`.
    public static func widthClass(for width: CGFloat) -> WatakeWidthClass {
        if width < regularBreakpoint {
            .compact
        } else if width < expandedBreakpoint {
            .regular
        } else {
            .expanded
        }
    }

    /// Outer content gutter for a width class (`Design.md` / `RESPONSIVE.md`).
    public static func gutter(for widthClass: WatakeWidthClass) -> CGFloat {
        switch widthClass {
        case .compact: WatakeSpacing.md
        case .regular: WatakeSpacing.xl
        case .expanded: WatakeSpacing.xxl
        }
    }

    /// Outer content gutter for a container width.
    public static func gutter(for width: CGFloat) -> CGFloat {
        gutter(for: widthClass(for: width))
    }

    /// Suggested column count for grid-style content (library folders, etc.).
    public static func columnCount(for widthClass: WatakeWidthClass) -> Int {
        switch widthClass {
        case .compact: 1
        case .regular: 2
        case .expanded: 3
        }
    }

    /// Suggested column count for a container width.
    public static func columnCount(for width: CGFloat) -> Int {
        columnCount(for: widthClass(for: width))
    }
}
