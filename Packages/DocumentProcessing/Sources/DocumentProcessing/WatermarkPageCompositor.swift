import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WatakeDomain

public enum WatermarkCompositionError: Error, Equatable, Sendable {
    case sourceUndecodable
    case imageUndecodable
    case invisibleWatermark
    case invalidColorHex
    case contextUnavailable
    case encodingFailed
}

/// The single bitmap composition path used by both live previews and durable
/// rendition pages. Preview output only changes the source decode bound; all
/// layer placement and drawing math is identical.
public actor WatermarkPageCompositor {
    public init() {}

    public func renderJPEG(
        sourceData: Data,
        config: WatermarkConfig,
        imageData: Data? = nil,
        maximumPixelDimension: Int? = nil,
        quality: Double = 0.95
    ) throws -> Data {
        try config.validate()
        guard config.hasVisibleLayer else {
            throw WatermarkCompositionError.invisibleWatermark
        }
        guard let source = decode(sourceData, maximumPixelDimension: maximumPixelDimension) else {
            throw WatermarkCompositionError.sourceUndecodable
        }
        let logo = try config.image.flatMap { layer -> CGImage? in
            guard layer.enabled else { return nil }
            guard let imageData, let image = decode(imageData, maximumPixelDimension: nil) else {
                throw WatermarkCompositionError.imageUndecodable
            }
            return image
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // JPEG has no alpha channel. Transparent source pixels are
        // intentionally flattened over white before watermark composition.
        guard let context = CGContext(
            data: nil,
            width: source.width,
            height: source.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw WatermarkCompositionError.contextUnavailable }

        let page = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(page)
        context.draw(source, in: page)
        let points = compositionPoints(config: config)
        for point in points {
            try drawComposite(config: config, logo: logo, normalizedPoint: point, page: page, into: context)
        }
        guard let output = context.makeImage() else { throw WatermarkCompositionError.contextUnavailable }
        return try encodeJPEG(output, quality: quality)
    }

    private func decode(_ data: Data, maximumPixelDimension: Int?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else { return nil }
        let bound = min(maximumPixelDimension ?? max(width, height), max(width, height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: bound
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func compositionPoints(config: WatermarkConfig) -> [WatermarkTilePoint] {
        switch config.layoutMode {
        case .single:
            return [point(for: config.globalPosition)]
        case .tiled:
            guard let spacingX = config.tileSpacingX, let spacingY = config.tileSpacingY else { return [] }
            return WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: spacingX, tileSpacingY: spacingY)
        }
    }

    private func point(for position: WatermarkPosition) -> WatermarkTilePoint {
        switch position {
        case .topLeft: .init(normalizedX: 0.16, normalizedY: 0.84)
        case .topCenter: .init(normalizedX: 0.5, normalizedY: 0.84)
        case .topRight: .init(normalizedX: 0.84, normalizedY: 0.84)
        case .midLeft: .init(normalizedX: 0.16, normalizedY: 0.5)
        case .center: .init(normalizedX: 0.5, normalizedY: 0.5)
        case .midRight: .init(normalizedX: 0.84, normalizedY: 0.5)
        case .botLeft: .init(normalizedX: 0.16, normalizedY: 0.16)
        case .botCenter: .init(normalizedX: 0.5, normalizedY: 0.16)
        case .botRight: .init(normalizedX: 0.84, normalizedY: 0.16)
        }
    }

    private func drawComposite(
        config: WatermarkConfig,
        logo: CGImage?,
        normalizedPoint: WatermarkTilePoint,
        page: CGRect,
        into context: CGContext
    ) throws {
        let metrics = compositeMetrics(config: config, hasLogo: logo != nil, page: page)
        let anchor = CGPoint(x: normalizedPoint.normalizedX * page.width, y: normalizedPoint.normalizedY * page.height)

        context.saveGState()
        context.translateBy(x: anchor.x, y: anchor.y)
        context.rotate(by: config.globalRotation * .pi / 180)
        context.setAlpha(config.globalOpacity)
        let origin = CGPoint(x: -metrics.width / 2, y: -metrics.height / 2)
        if let logo, let layer = config.image, metrics.placement == .behindText {
            try drawLogo(
                logo,
                layer: layer,
                rect: centeredRect(origin: origin, size: metrics.width, height: metrics.height, side: metrics.logoSide),
                into: context
            )
        }
        let textOriginX: CGFloat = if metrics.horizontal && metrics.placement == .leftOfText {
            origin.x + metrics.logoSide + metrics.spacing
        } else {
            origin.x
        }
        try drawTextLayers(
            metrics.layers,
            heights: metrics.textHeights,
            layout: TextLayout(
                originX: textOriginX,
                centerY: 0,
                width: metrics.textWidth,
                totalHeight: metrics.textHeight,
                minimum: metrics.minimum
            ),
            into: context
        )
        if let logo, let layer = config.image, metrics.placement != .behindText {
            let rect: CGRect = if metrics.horizontal {
                CGRect(
                    x: metrics.placement == .leftOfText ? origin.x : origin.x + metrics.textWidth + metrics.spacing,
                    y: -metrics.logoSide / 2,
                    width: metrics.logoSide,
                    height: metrics.logoSide
                )
            } else {
                centeredRect(origin: origin, size: metrics.width, height: metrics.height, side: metrics.logoSide)
            }
            try drawLogo(logo, layer: layer, rect: rect, into: context)
        }
        context.restoreGState()
    }

    private func compositeMetrics(config: WatermarkConfig, hasLogo: Bool, page: CGRect) -> CompositeMetrics {
        let minimum = min(page.width, page.height)
        let layers = config.renderableTextLayersInCompositionOrder
        let textHeights = layers.map { measuredHeight($0, minimum: minimum) }
        let textHeight = textHeights.reduce(0, +)
        let textWidth = layers.map { measuredWidth($0, minimum: minimum) }.max() ?? 0
        let logoSide = config.image.map { minimum * 0.20 * $0.scale } ?? 0
        let spacing = minimum * 0.025
        let placement = config.image?.placement ?? .behindText
        let horizontal = hasLogo && (placement == .leftOfText || placement == .rightOfText)
        return CompositeMetrics(
            minimum: minimum,
            layers: layers,
            textHeights: textHeights,
            textHeight: textHeight,
            textWidth: textWidth,
            logoSide: logoSide,
            spacing: spacing,
            placement: placement,
            horizontal: horizontal,
            width: horizontal ? textWidth + logoSide + spacing : max(textWidth, logoSide),
            height: max(textHeight, logoSide)
        )
    }

    private func centeredRect(origin: CGPoint, size: CGFloat, height: CGFloat, side: CGFloat) -> CGRect {
        CGRect(x: origin.x + (size - side) / 2, y: origin.y + (height - side) / 2, width: side, height: side)
    }

    private func drawTextLayers(
        _ layers: [WatermarkTextLayer],
        heights: [CGFloat],
        layout: TextLayout,
        into context: CGContext
    ) throws {
        var cursor = layout.centerY + layout.totalHeight / 2
        for (layer, height) in zip(layers, heights) {
            let size = fontSize(layer.sizePreset, minimum: layout.minimum)
            cursor -= height
            context.saveGState()
            context.translateBy(x: layout.originX + layout.width / 2, y: cursor + height / 2)
            context.rotate(by: layer.rotation * .pi / 180)
            let color = try cgColor(layer.colorHex, alpha: layer.opacity)
            let font = WatermarkFontResolver.resolveFont(named: layer.fontName, pointSize: size)
            var alignment = CTTextAlignment.center
            let paragraph = withUnsafeBytes(of: &alignment) { bytes in
                guard let value = bytes.baseAddress else { return CTParagraphStyleCreate(nil, 0) }
                let setting = CTParagraphStyleSetting(
                    spec: .alignment,
                    valueSize: bytes.count,
                    value: value
                )
                return CTParagraphStyleCreate([setting], 1)
            }
            let attributed = NSAttributedString(string: layer.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let path = CGPath(
                rect: CGRect(x: -layout.width / 2, y: -height / 2, width: layout.width, height: height),
                transform: nil
            )
            CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), path, nil), context)
            context.restoreGState()
        }
    }

    private func drawLogo(_ image: CGImage, layer: WatermarkImageLayer, rect: CGRect, into context: CGContext) throws {
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: layer.rotation * .pi / 180)
        let target = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
        context.setAlpha(layer.opacity)
        context.draw(image, in: target)
        if let tint = layer.tintHex {
            context.setBlendMode(.sourceAtop)
            try context.setFillColor(cgColor(tint, alpha: layer.opacity))
            context.fill(target)
        }
        context.restoreGState()
    }

    private func fontSize(_ preset: WatermarkSizePreset, minimum: CGFloat) -> CGFloat {
        switch preset {
        case .small: minimum * 0.025
        case .medium: minimum * 0.04
        case .large: minimum * 0.06
        }
    }

    private func measuredWidth(_ layer: WatermarkTextLayer, minimum: CGFloat) -> CGFloat {
        let font = WatermarkFontResolver.resolveFont(named: layer.fontName, pointSize: fontSize(layer.sizePreset, minimum: minimum))
        let attributed = NSAttributedString(string: layer.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        return min(
            max(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil), minimum * 0.18),
            minimum * 0.75
        )
    }

    private func measuredHeight(_ layer: WatermarkTextLayer, minimum: CGFloat) -> CGFloat {
        let lineHeight = fontSize(layer.sizePreset, minimum: minimum) * 1.35
        let lineCount = max(layer.text.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        return lineHeight * CGFloat(lineCount)
    }

    private func cgColor(_ hex: String, alpha: Double) throws -> CGColor {
        guard hex.count == 7, hex.first == "#", let value = UInt64(hex.dropFirst(), radix: 16) else {
            throw WatermarkCompositionError.invalidColorHex
        }
        return CGColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    private func encodeJPEG(_ image: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw WatermarkCompositionError.encodingFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw WatermarkCompositionError.encodingFailed }
        return output as Data
    }
}

private struct TextLayout {
    let originX: CGFloat
    let centerY: CGFloat
    let width: CGFloat
    let totalHeight: CGFloat
    let minimum: CGFloat
}

private struct CompositeMetrics {
    let minimum: CGFloat
    let layers: [WatermarkTextLayer]
    let textHeights: [CGFloat]
    let textHeight: CGFloat
    let textWidth: CGFloat
    let logoSide: CGFloat
    let spacing: CGFloat
    let placement: WatermarkImagePlacement
    let horizontal: Bool
    let width: CGFloat
    let height: CGFloat
}
