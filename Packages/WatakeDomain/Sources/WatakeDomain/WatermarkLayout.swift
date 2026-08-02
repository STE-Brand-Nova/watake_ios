import Foundation

public enum WatermarkHorizontalAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}

public enum WatermarkVerticalAlignment: Equatable, Sendable {
    case top
    case center
    case bottom
}

/// Converts a validated `#RRGGBB` contract hex string into unit-interval RGB
/// components at the platform rendering boundary. Callers must pass a value
/// that already satisfies `WatakeDomain` color validation.
public struct WatermarkColorComponents: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    /// `hex` must already be validated as `#RRGGBB` by `WatakeDomain`.
    /// Falls back to opaque black only if that domain guarantee is somehow
    /// violated, since a watermark must never fail to render over a missing
    /// color.
    public init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            red = 0
            green = 0
            blue = 0
            return
        }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }
}

/// A single text layer's placement, sized, and styled independent of any
/// concrete page's pixel dimensions, so the same model can drive both PDF
/// rendering and a future live preview. Pure `Double` coordinates only —
/// platform coordinate types (e.g. `CGPoint`) are the renderer's concern.
///
/// `normalizedAnchorX`/`normalizedAnchorY` are fractions of the page's width
/// and height respectively, with `normalizedAnchorY` measured **from the
/// top** of the page (matching the `topLeft`/`botRight` naming in
/// `WatermarkPosition`). Callers converting to a Core Graphics (bottom-left
/// origin) coordinate space must flip: `y = pageHeight * (1 - normalizedAnchorY)`.
///
/// `normalizedFontSize` is a fraction of the page's shorter edge, so text
/// scales consistently across portrait and landscape pages.
public struct WatermarkLayout: Equatable, Sendable {
    public let normalizedAnchorX: Double
    public let normalizedAnchorY: Double
    public let horizontalAlignment: WatermarkHorizontalAlignment
    public let verticalAlignment: WatermarkVerticalAlignment
    public let normalizedFontSize: Double
    public let rotationDegrees: Double
    public let opacity: Double
    public let color: WatermarkColorComponents

    public init(
        normalizedAnchorX: Double,
        normalizedAnchorY: Double,
        horizontalAlignment: WatermarkHorizontalAlignment,
        verticalAlignment: WatermarkVerticalAlignment,
        normalizedFontSize: Double,
        rotationDegrees: Double,
        opacity: Double,
        color: WatermarkColorComponents
    ) {
        self.normalizedAnchorX = normalizedAnchorX
        self.normalizedAnchorY = normalizedAnchorY
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.normalizedFontSize = normalizedFontSize
        self.rotationDegrees = rotationDegrees
        self.opacity = opacity
        self.color = color
    }

    public func fontPointSize(pageWidth: Double, pageHeight: Double) -> Double {
        normalizedFontSize * min(pageWidth, pageHeight)
    }

    /// Anchor position in a bottom-left-origin coordinate space, as plain
    /// `Double`s. Renderer wraps this into a platform point type.
    public func anchor(pageWidth: Double, pageHeight: Double) -> (x: Double, y: Double) {
        let anchorX = normalizedAnchorX * pageWidth
        let anchorY = pageHeight * (1 - normalizedAnchorY)
        return (anchorX, anchorY)
    }
}

/// Position and alignment for a watermark anchor, independent of any
/// concrete page's pixel dimensions.
struct WatermarkAnchorPlacement {
    let normalizedX: Double
    let normalizedY: Double
    let horizontal: WatermarkHorizontalAlignment
    let vertical: WatermarkVerticalAlignment
}

public enum WatermarkLayoutCalculator {
    /// Fraction of page width/height reserved as margin from each edge.
    private static let edgeMargin = 0.05

    /// Deterministic size-preset mapping: fraction of the page's shorter
    /// edge used as the rendered font point size.
    private static func normalizedFontSize(for preset: WatermarkSizePreset) -> Double {
        switch preset {
        case .small: 0.028
        case .medium: 0.045
        case .large: 0.065
        }
    }

    private static func anchor(for position: WatermarkPosition) -> WatermarkAnchorPlacement {
        let leadingX = edgeMargin
        let centerX = 0.5
        let trailingX = 1 - edgeMargin
        let topY = edgeMargin
        let centerY = 0.5
        let bottomY = 1 - edgeMargin

        let normalizedX: Double
        let normalizedY: Double
        let horizontal: WatermarkHorizontalAlignment
        let vertical: WatermarkVerticalAlignment

        switch position {
        case .topLeft: (normalizedX, normalizedY, horizontal, vertical) = (leadingX, topY, .leading, .top)
        case .topCenter: (normalizedX, normalizedY, horizontal, vertical) = (centerX, topY, .center, .top)
        case .topRight: (normalizedX, normalizedY, horizontal, vertical) = (trailingX, topY, .trailing, .top)
        case .midLeft: (normalizedX, normalizedY, horizontal, vertical) = (leadingX, centerY, .leading, .center)
        case .center: (normalizedX, normalizedY, horizontal, vertical) = (centerX, centerY, .center, .center)
        case .midRight: (normalizedX, normalizedY, horizontal, vertical) = (trailingX, centerY, .trailing, .center)
        case .botLeft: (normalizedX, normalizedY, horizontal, vertical) = (leadingX, bottomY, .leading, .bottom)
        case .botCenter: (normalizedX, normalizedY, horizontal, vertical) = (centerX, bottomY, .center, .bottom)
        case .botRight: (normalizedX, normalizedY, horizontal, vertical) = (trailingX, bottomY, .trailing, .bottom)
        }

        return WatermarkAnchorPlacement(normalizedX: normalizedX, normalizedY: normalizedY, horizontal: horizontal, vertical: vertical)
    }

    public static func makeLayout(bodyLayer: WatermarkTextLayer, config: WatermarkConfig) -> WatermarkLayout {
        let placement = anchor(for: config.globalPosition)
        let combinedOpacity = min(max(bodyLayer.opacity * config.globalOpacity, 0), 1)
        let combinedRotation = bodyLayer.rotation + config.globalRotation

        return WatermarkLayout(
            normalizedAnchorX: placement.normalizedX,
            normalizedAnchorY: placement.normalizedY,
            horizontalAlignment: placement.horizontal,
            verticalAlignment: placement.vertical,
            normalizedFontSize: normalizedFontSize(for: bodyLayer.sizePreset),
            rotationDegrees: combinedRotation,
            opacity: combinedOpacity,
            color: WatermarkColorComponents(hex: bodyLayer.colorHex)
        )
    }
}
