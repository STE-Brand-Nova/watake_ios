import CoreGraphics

// t-shirt scale tokens are intentionally short; suppression scoped to this file.
// swiftlint:disable identifier_name

/// The spacing scale from `Design.md`: `4, 8, 12, 16, 20, 24, 32, 40, 48, 64`.
///
/// Features use named steps only; literal spacing values are not allowed outside
/// this file.
public enum WatakeSpacing {
    /// 4pt
    public static let xxs: CGFloat = 4
    /// 8pt
    public static let xs: CGFloat = 8
    /// 12pt
    public static let sm: CGFloat = 12
    /// 16pt
    public static let md: CGFloat = 16
    /// 20pt
    public static let lg: CGFloat = 20
    /// 24pt
    public static let xl: CGFloat = 24
    /// 32pt
    public static let xxl: CGFloat = 32
    /// 40pt
    public static let xxxl: CGFloat = 40
    /// 48pt
    public static let xxxxl: CGFloat = 48
    /// 64pt
    public static let huge: CGFloat = 64

    /// Ordered scale, exposed for validation and tests.
    public static let scale: [CGFloat] = [xxs, xs, sm, md, lg, xl, xxl, xxxl, xxxxl, huge]
}

// swiftlint:enable identifier_name
