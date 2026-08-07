import Foundation

/// A single tile's center, normalized to the unit square with the same
/// top-left-origin convention as `WatermarkLayout.normalizedAnchorY`. Values
/// near the page edges intentionally fall outside `0...1` so edge tiles are
/// only partially visible; renderers clip to the fitted page.
public struct WatermarkTilePoint: Equatable, Sendable {
    public let normalizedX: Double
    public let normalizedY: Double

    public init(normalizedX: Double, normalizedY: Double) {
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
    }
}

/// Pure, platform-neutral tile-grid math shared by the editor preview and any
/// future renderer. `tileSpacingX`/`tileSpacingY` are normalized distances
/// between tile centers relative to page width/height respectively (the
/// `WatermarkConfig` contract). Because both axes are already normalized
/// per-axis, the grid is decoupled from the page's actual aspect ratio: the
/// same normalized points cover a portrait or landscape page equally once a
/// caller multiplies by that page's own width/height.
public enum WatermarkTileLayoutCalculator {
    /// At the domain's minimum allowed spacing (0.10) in both axes this cap
    /// is reached exactly (11 columns x 11 rows). Any spacing within the
    /// valid contract range therefore never hits the ceiling; it exists so a
    /// malformed input can never make tiling grow unbounded.
    public static let maximumTileCount = 121

    private static let minimumSpacing = 0.10
    private static let maximumSpacing = 1.00

    /// Deterministic row-major tile centers anchored on the page center
    /// (0.5, 0.5). Same input always produces the same output.
    public static func tilePoints(tileSpacingX: Double, tileSpacingY: Double) -> [WatermarkTilePoint] {
        let spacingX = clampedSpacing(tileSpacingX)
        let spacingY = clampedSpacing(tileSpacingY)
        let stepsX = stepCount(for: spacingX)
        let stepsY = stepCount(for: spacingY)

        var points: [WatermarkTilePoint] = []
        rows: for rowOffset in -stepsY ... stepsY {
            let centerY = 0.5 + Double(rowOffset) * spacingY
            for columnOffset in -stepsX ... stepsX {
                let centerX = 0.5 + Double(columnOffset) * spacingX
                points.append(WatermarkTilePoint(normalizedX: centerX, normalizedY: centerY))
                if points.count >= maximumTileCount {
                    break rows
                }
            }
        }
        return points
    }

    /// Convenience for callers holding a `WatermarkConfig`. Returns a single
    /// page-center point for `.single` layout, or an empty array when tiled
    /// spacing is missing (a config that failed contract validation).
    public static func tilePoints(for config: WatermarkConfig) -> [WatermarkTilePoint] {
        switch config.layoutMode {
        case .single:
            [WatermarkTilePoint(normalizedX: 0.5, normalizedY: 0.5)]
        case .tiled:
            if let tileSpacingX = config.tileSpacingX, let tileSpacingY = config.tileSpacingY {
                tilePoints(tileSpacingX: tileSpacingX, tileSpacingY: tileSpacingY)
            } else {
                []
            }
        }
    }

    /// Smallest step count on one side of center such that the grid reaches
    /// or passes both page edges (distance 0.5 from center in each
    /// direction).
    private static func stepCount(for spacing: Double) -> Int {
        Int((0.5 / spacing).rounded(.up))
    }

    /// NaN and infinite values fail `isFinite` and fall back to the widest
    /// (safest, fewest-tiles) spacing rather than dividing by zero or
    /// producing non-finite coordinates.
    private static func clampedSpacing(_ value: Double) -> Double {
        guard value.isFinite else { return maximumSpacing }
        return min(max(value, minimumSpacing), maximumSpacing)
    }
}
