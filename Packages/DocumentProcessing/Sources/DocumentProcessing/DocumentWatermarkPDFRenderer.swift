import CoreGraphics
import CoreText
import Foundation
import ImageIO
import WatakeDomain

/// Renders one PDF page per source `DocumentPage`, in ascending `index`
/// order, optionally drawing the enabled `WatermarkConfig.body` text layer.
/// Source assets are only ever read, never mutated. Output is transient PDF
/// data held fully in memory (`NSMutableData` via `CGDataConsumer`) — fine
/// for the current unwired processing boundary, but unsafe for large scans
/// once a real export path exists. Switch to temporary-file-backed output
/// with cleanup on failure/cancellation before wiring this to export UI.
public actor DocumentWatermarkPDFRenderer: WatermarkPDFRendering {
    private let assetStore: any DocumentAssetStore

    public init(assetStore: any DocumentAssetStore) {
        self.assetStore = assetStore
    }

    public func renderPDF(for document: StoredDocument, watermark config: WatermarkConfig) async throws -> Data {
        try Task.checkCancellation()
        try Self.validateContract(document: document, config: config)
        try Self.validateSupportedConfiguration(config)

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw WatermarkRenderError.pdfGenerationFailed
        }
        guard let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw WatermarkRenderError.pdfGenerationFailed
        }

        let orderedPages = document.pages.sorted { $0.index < $1.index }
        for page in orderedPages {
            try Task.checkCancellation()
            try await renderPage(page, config: config, into: context)
        }
        context.closePDF()

        return pdfData as Data
    }

    private func renderPage(_ page: DocumentPage, config: WatermarkConfig, into context: CGContext) async throws {
        let sourceData: Data
        do {
            sourceData = try await assetStore.readAsset(page.source)
        } catch {
            throw WatermarkRenderError.sourceAssetUnreadable(pageIndex: page.index)
        }

        guard let cgImage = Self.decodeImage(from: sourceData) else {
            throw WatermarkRenderError.sourceImageUndecodable(pageIndex: page.index)
        }
        let pageWidth = Double(cgImage.width)
        let pageHeight = Double(cgImage.height)
        guard pageWidth > 0, pageHeight > 0 else {
            throw WatermarkRenderError.sourceImageEmpty(pageIndex: page.index)
        }

        try Task.checkCancellation()

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let mediaBoxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)
        context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBoxData] as CFDictionary)
        context.draw(cgImage, in: mediaBox)

        if let bodyLayer = config.body, Self.isRenderable(bodyLayer) {
            let layout = WatermarkLayoutCalculator.makeLayout(bodyLayer: bodyLayer, config: config)
            let pageSize = CGSize(width: pageWidth, height: pageHeight)
            Self.drawText(bodyLayer.text, fontName: bodyLayer.fontName, layout: layout, pageSize: pageSize, into: context)
        }

        context.endPDFPage()
    }

    private static func isRenderable(_ layer: WatermarkTextLayer) -> Bool {
        layer.enabled && !layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Validates the domain contract before any rendering work starts, so a
    /// malformed `StoredDocument` or `WatermarkConfig` (e.g. an invalid color
    /// hex) never falls through to a silent fallback (such as black text)
    /// inside the renderer. Kept as two calls so document vs. config failures
    /// map to distinct, accurate errors.
    private static func validateContract(document: StoredDocument, config: WatermarkConfig) throws {
        do {
            try document.validate()
        } catch {
            throw WatermarkRenderError.invalidDocument
        }
        do {
            try config.validate()
        } catch {
            throw WatermarkRenderError.invalidWatermarkConfig
        }
    }

    private static func validateSupportedConfiguration(_ config: WatermarkConfig) throws {
        guard config.layoutMode == .single else {
            throw WatermarkRenderError.unsupportedLayoutMode(config.layoutMode)
        }
        if let heading = config.heading, isRenderable(heading) {
            throw WatermarkRenderError.unsupportedWatermarkLayer(.heading)
        }
        if let caption = config.caption, isRenderable(caption) {
            throw WatermarkRenderError.unsupportedWatermarkLayer(.caption)
        }
        if let image = config.image, image.enabled {
            throw WatermarkRenderError.unsupportedWatermarkLayer(.image)
        }
    }

    private static func decodeImage(from data: Data) -> CGImage? {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func drawText(
        _ text: String,
        fontName: String,
        layout: WatermarkLayout,
        pageSize: CGSize,
        into context: CGContext
    ) {
        let fontSize = layout.fontPointSize(pageWidth: pageSize.width, pageHeight: pageSize.height)
        let font = WatermarkFontResolver.resolveFont(named: fontName, pointSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        let originX: Double = switch layout.horizontalAlignment {
        case .leading: 0
        case .center: -lineWidth / 2
        case .trailing: -lineWidth
        }

        let originY: Double = switch layout.verticalAlignment {
        case .top: -Double(ascent)
        case .center: -(Double(ascent) - Double(descent)) / 2
        case .bottom: Double(descent)
        }

        let anchorCoordinates = layout.anchor(pageWidth: pageSize.width, pageHeight: pageSize.height)
        let anchor = CGPoint(x: anchorCoordinates.x, y: anchorCoordinates.y)

        context.saveGState()
        context.setFillColor(
            red: layout.color.red,
            green: layout.color.green,
            blue: layout.color.blue,
            alpha: layout.opacity
        )
        context.translateBy(x: anchor.x, y: anchor.y)
        context.rotate(by: layout.rotationDegrees * .pi / 180)
        context.textPosition = CGPoint(x: originX, y: originY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
