import CoreGraphics
import Foundation
import ImageIO
import WatakeDomain

/// Compatibility PDF boundary backed by the same compositor as issuance
/// previews and persisted rendition pages. New sharing paths assemble PDFs
/// from persisted rendition JPEGs; this in-memory API remains for callers of
/// the original `WatermarkPDFRendering` port.
public actor DocumentWatermarkPDFRenderer: WatermarkPDFRendering {
    private let assetStore: any DocumentAssetStore
    private let compositor: WatermarkPageCompositor

    public init(
        assetStore: any DocumentAssetStore,
        compositor: WatermarkPageCompositor = WatermarkPageCompositor()
    ) {
        self.assetStore = assetStore
        self.compositor = compositor
    }

    public func renderPDF(for document: StoredDocument, watermark config: WatermarkConfig) async throws -> Data {
        try Task.checkCancellation()
        try Self.validateContract(document: document, config: config)
        let imageData = try await loadWatermarkImage(config.image)
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw WatermarkRenderError.pdfGenerationFailed
        }
        guard let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw WatermarkRenderError.pdfGenerationFailed
        }

        for page in document.pages.sorted(by: { $0.index < $1.index }) {
            try Task.checkCancellation()
            try await renderPage(page, config: config, imageData: imageData, into: context)
        }
        context.closePDF()
        return pdfData as Data
    }

    private func loadWatermarkImage(_ layer: WatermarkImageLayer?) async throws -> Data? {
        guard let layer, layer.enabled else { return nil }
        do {
            return try await assetStore.readAsset(layer.assetRef)
        } catch {
            throw WatermarkRenderError.watermarkImageAssetUnreadable
        }
    }

    private func renderPage(
        _ page: DocumentPage,
        config: WatermarkConfig,
        imageData: Data?,
        into context: CGContext
    ) async throws {
        let sourceData: Data
        do {
            sourceData = try await assetStore.readAsset(page.rectified ?? page.source)
        } catch {
            throw WatermarkRenderError.sourceAssetUnreadable(pageIndex: page.index)
        }

        let renderedData: Data
        if Self.hasVisibleWatermark(config) {
            do {
                renderedData = try await compositor.renderJPEG(
                    sourceData: sourceData,
                    config: config,
                    imageData: imageData
                )
            } catch WatermarkCompositionError.imageUndecodable {
                throw WatermarkRenderError.watermarkImageUndecodable
            } catch WatermarkCompositionError.sourceUndecodable {
                throw WatermarkRenderError.sourceImageUndecodable(pageIndex: page.index)
            } catch {
                throw WatermarkRenderError.pdfGenerationFailed
            }
        } else {
            renderedData = sourceData
        }

        guard let image = Self.decodeImage(from: renderedData) else {
            throw WatermarkRenderError.sourceImageUndecodable(pageIndex: page.index)
        }
        guard image.width > 0, image.height > 0 else {
            throw WatermarkRenderError.sourceImageEmpty(pageIndex: page.index)
        }
        var mediaBox = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let mediaBoxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)
        context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBoxData] as CFDictionary)
        context.draw(image, in: mediaBox)
        context.endPDFPage()
    }

    private static func hasVisibleWatermark(_ config: WatermarkConfig) -> Bool {
        config.globalOpacity > 0 && (
            config.renderableTextLayersInCompositionOrder.contains(where: { $0.opacity > 0 }) ||
                (config.image?.enabled == true && config.image?.opacity ?? 0 > 0)
        )
    }

    private static func validateContract(document: StoredDocument, config: WatermarkConfig) throws {
        do { try document.validate() } catch { throw WatermarkRenderError.invalidDocument }
        do { try config.validate() } catch { throw WatermarkRenderError.invalidWatermarkConfig }
    }

    private static func decodeImage(from data: Data) -> CGImage? {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
