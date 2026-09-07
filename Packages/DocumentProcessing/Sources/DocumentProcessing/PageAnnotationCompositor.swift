import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WatakeDomain

public enum PageAnnotationRenderError: Error, Equatable, Sendable {
    case sourceUndecodable
    case imageUnavailable
    case imageUndecodable
    case invalidAnnotation
    case invalidColor
    case contextUnavailable
    case encodingFailed
}

/// Canonical source + editable-layer renderer. Every consumer uses this actor,
/// while interactive SwiftUI overlays use the same normalized transform model.
public actor PageAnnotationCompositor: PageAnnotationRendering {
    private let assetStore: any DocumentAssetStore

    public init(assetStore: any DocumentAssetStore) {
        self.assetStore = assetStore
    }

    public func renderJPEG(
        sourceData: Data,
        annotations: [PageAnnotation],
        maximumPixelDimension: Int? = nil,
        quality: Double = 0.95
    ) async throws -> Data {
        do { try annotations.forEach { try $0.validate() } } catch {
            throw PageAnnotationRenderError.invalidAnnotation
        }
        guard let source = decode(sourceData, maximumPixelDimension: maximumPixelDimension) else {
            throw PageAnnotationRenderError.sourceUndecodable
        }
        var images: [UUID: CGImage] = [:]
        for reference in annotations.compactMap(\.image) {
            let data: Data
            do { data = try await assetStore.readAsset(reference) } catch {
                throw PageAnnotationRenderError.imageUnavailable
            }
            guard let image = decode(data, maximumPixelDimension: max(source.width, source.height)) else {
                throw PageAnnotationRenderError.imageUndecodable
            }
            images[reference.id] = image
        }

        guard let context = CGContext(
            data: nil,
            width: source.width,
            height: source.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw PageAnnotationRenderError.contextUnavailable }
        let page = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(page)
        context.draw(source, in: page)
        for annotation in annotations.sorted(by: Self.layerOrder) {
            try draw(annotation, image: annotation.image.flatMap { images[$0.id] }, page: page, into: context)
        }
        guard let output = context.makeImage() else { throw PageAnnotationRenderError.contextUnavailable }
        return try encodeJPEG(output, quality: quality)
    }

    private static func layerOrder(_ lhs: PageAnnotation, _ rhs: PageAnnotation) -> Bool {
        lhs.zIndex != rhs.zIndex ? lhs.zIndex < rhs.zIndex : lhs.id.uuidString < rhs.id.uuidString
    }

    private func draw(_ annotation: PageAnnotation, image: CGImage?, page: CGRect, into context: CGContext) throws {
        let transform = annotation.transform
        let width = page.width * transform.width
        let height = page.height * transform.height
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: page.width * transform.centerX, y: page.height * (1 - transform.centerY))
        context.rotate(by: transform.rotation * .pi / 180)
        context.setAlpha(annotation.opacity)
        switch annotation.kind {
        case .text:
            guard let text = annotation.text else { throw PageAnnotationRenderError.invalidAnnotation }
            try drawText(text, in: rect, page: page, into: context)
        case .signature:
            try drawStrokes(annotation.strokes, in: rect, page: page, highlight: false, into: context)
        case .image:
            guard let image else { throw PageAnnotationRenderError.imageUnavailable }
            drawAspectFit(image, in: rect, into: context)
        case .highlight:
            try drawStrokes(annotation.strokes, in: rect, page: page, highlight: true, into: context)
        }
    }

    private func drawText(_ text: AnnotationText, in rect: CGRect, page: CGRect, into context: CGContext) throws {
        var font = WatermarkFontResolver.resolveFont(
            named: text.fontName,
            pointSize: min(page.width, page.height) * text.fontSize
        )
        var traits: CTFontSymbolicTraits = []
        if text.isBold {
            traits.insert(.traitBold)
        }
        if text.isItalic {
            traits.insert(.traitItalic)
        }
        if !traits.isEmpty, let styled = CTFontCreateCopyWithSymbolicTraits(font, 0, nil, traits, traits) {
            font = styled
        }
        var alignment: CTTextAlignment = switch text.alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        let paragraph = withUnsafeBytes(of: &alignment) { bytes -> CTParagraphStyle in
            guard let address = bytes.baseAddress else { return CTParagraphStyleCreate(nil, 0) }
            let setting = CTParagraphStyleSetting(spec: .alignment, valueSize: bytes.count, value: address)
            return CTParagraphStyleCreate([setting], 1)
        }
        var attributes: [NSAttributedString.Key: Any] = try [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(text.colorHex, alpha: 1),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
        ]
        if text.isUnderlined {
            attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = 1
        }
        let attributed = NSAttributedString(string: text.text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: rect, transform: nil), nil), context)
    }

    private func drawStrokes(
        _ strokes: [InkStroke],
        in rect: CGRect,
        page: CGRect,
        highlight: Bool,
        into context: CGContext
    ) throws {
        if highlight {
            context.setBlendMode(.multiply)
        }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            context.beginPath()
            context.move(to: strokePoint(first, in: rect))
            for point in stroke.points.dropFirst() {
                context.addLine(to: strokePoint(point, in: rect))
            }
            try context.setStrokeColor(color(stroke.colorHex, alpha: stroke.opacity))
            let pressure = stroke.points.map(\.pressure).reduce(0, +) / Double(stroke.points.count)
            context.setLineWidth(min(page.width, page.height) * stroke.width * max(0.2, pressure))
            context.strokePath()
        }
    }

    private func strokePoint(_ point: InkPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * point.location.x, y: rect.minY + rect.height * (1 - point.location.y))
    }

    private func drawAspectFit(_ image: CGImage, in rect: CGRect, into context: CGContext) {
        let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        context.draw(image, in: target)
    }

    private func color(_ hex: String, alpha: Double) throws -> CGColor {
        guard hex.count == 7, hex.first == "#", let value = Int(hex.dropFirst(), radix: 16) else {
            throw PageAnnotationRenderError.invalidColor
        }
        return CGColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
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

    private func encodeJPEG(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PageAnnotationRenderError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PageAnnotationRenderError.encodingFailed }
        return data as Data
    }
}
