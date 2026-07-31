import CoreGraphics

// t-shirt scale tokens are intentionally short; suppression scoped to this file.
// swiftlint:disable identifier_name

/// Corner-radius tokens from `Design.md`.
public enum WatakeRadius {
    /// 8pt — chips, small controls.
    public static let sm: CGFloat = 8
    /// 12pt — cards, fields.
    public static let md: CGFloat = 12
    /// 16pt — large cards, sheets.
    public static let lg: CGFloat = 16
    /// 24pt — prominent containers.
    public static let xl: CGFloat = 24
    /// Fully rounded (pill / capsule).
    public static let pill: CGFloat = 999
}

// swiftlint:enable identifier_name
