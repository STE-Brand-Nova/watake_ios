import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WatakeDomain

/// Actor responsible for rendering a sequence of document pages into a single PDF
/// file directly to disk, keeping memory overhead low by streaming pages and downsampling
/// source images based on the target page size.
public actor BulkPDFRenderer: BulkPDFExporting {
    private let assetStore: any DocumentAssetStore

    public init(assetStore: any DocumentAssetStore) {
        self.assetStore = assetStore
    }

    public func renderPDF(
        job: PDFRenderJob,
        progress: @Sendable (ExportProgress) -> Void
    ) async throws -> URL {
        try Task.checkCancellation()

        let fileManager = FileManager.default

        // Clean up partial file on failure or cancellation
        var success = false
        defer {
            if !success {
                try? fileManager.removeItem(at: job.outputURL)
            }
        }

        // Initialize PDF context pointing directly to the output URL
        guard let pdfContext = CGContext(job.outputURL as CFURL, mediaBox: nil, nil) else {
            throw ExportError.pdfContextFailed
        }

        // Close the PDF context when we are done
        defer {
            pdfContext.closePDF()
        }

        let totalPages = job.pages.count
        guard totalPages > 0 else {
            throw ExportError.emptyDraft
        }

        progress(ExportProgress(completedPages: 0, totalPages: totalPages, phase: .preparing))

        for (index, page) in job.pages.enumerated() {
            try Task.checkCancellation()

            progress(ExportProgress(completedPages: index, totalPages: totalPages, phase: .rendering(pageIndex: index)))

            // Load asset data
            let sourceData: Data
            do {
                sourceData = try await assetStore.readAsset(page.assetReference)
            } catch {
                throw ExportError.assetUnreadable(pageID: page.id)
            }

            try Task.checkCancellation()

            try renderPage(
                data: sourceData,
                pageID: page.id,
                job: job,
                into: pdfContext
            )
        }

        try Task.checkCancellation()
        progress(ExportProgress(completedPages: totalPages, totalPages: totalPages, phase: .finishing))

        // Ensure the context is flushed and closed
        pdfContext.closePDF()

        // Verify output file exists and is readable
        guard fileManager.isReadableFile(atPath: job.outputURL.path) else {
            throw ExportError.outputWriteFailed
        }

        success = true
        return job.outputURL
    }

    private func renderPage(
        data: Data,
        pageID: UUID,
        job: PDFRenderJob,
        into context: CGContext
    ) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ExportError.imageUndecodable(pageID: pageID)
        }

        let layout = try computePageLayout(source: source, pageID: pageID, job: job)

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: layout.maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw ExportError.imageUndecodable(pageID: pageID)
        }

        drawPDFPage(cgImage: cgImage, layout: layout, fitMode: job.fitMode, into: context)
    }

    private struct RenderLayout {
        let mediaBox: ExportPageGeometry.PageRect
        let transform: ExportPageGeometry.PageTransform
        let maxPixelSize: Int
        let appliedWidth: Double
        let appliedHeight: Double
    }

    private func computePageLayout(
        source: CGImageSource,
        pageID: UUID,
        job: PDFRenderJob
    ) throws -> RenderLayout {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Double
        let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Double
        guard let pixelWidth, let pixelHeight else {
            throw ExportError.imageEmpty(pageID: pageID)
        }

        guard pixelWidth > 0, pixelHeight > 0 else {
            throw ExportError.imageEmpty(pageID: pageID)
        }

        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        let applied = ExportPageGeometry.appliedOrientation(
            rawWidth: pixelWidth,
            rawHeight: pixelHeight,
            exifOrientation: orientation
        )

        let mediaBox = ExportPageGeometry.mediaBox(
            for: job.pageSize,
            sourceWidth: applied.width,
            sourceHeight: applied.height
        )

        let contentRect = try ExportPageGeometry.contentRect(
            mediaBox: mediaBox,
            marginPoints: job.marginPoints
        )

        let transform: ExportPageGeometry.PageTransform = switch job.fitMode {
        case .fit:
            ExportPageGeometry.fitTransform(sourceWidth: applied.width, sourceHeight: applied.height, contentRect: contentRect)
        case .fill:
            ExportPageGeometry.fillTransform(sourceWidth: applied.width, sourceHeight: applied.height, contentRect: contentRect)
        }

        let maxDims = ExportPageGeometry.maxPixelDimensions(
            sourceWidth: applied.width,
            sourceHeight: applied.height,
            contentRect: contentRect,
            fitMode: job.fitMode
        )

        return RenderLayout(
            mediaBox: mediaBox,
            transform: transform,
            maxPixelSize: max(maxDims.width, maxDims.height),
            appliedWidth: applied.width,
            appliedHeight: applied.height
        )
    }

    private func drawPDFPage(
        cgImage: CGImage,
        layout: RenderLayout,
        fitMode: ExportFitMode,
        into context: CGContext
    ) {
        let mediaBox = layout.mediaBox
        let transform = layout.transform

        var boxRect = CGRect(x: mediaBox.x, y: mediaBox.y, width: mediaBox.width, height: mediaBox.height)
        let boxData = Data(bytes: &boxRect, count: MemoryLayout<CGRect>.size)
        context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)

        context.saveGState()
        context.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        context.fill(CGRect(x: mediaBox.x, y: mediaBox.y, width: mediaBox.width, height: mediaBox.height))
        context.restoreGState()

        context.saveGState()
        if fitMode == .fill {
            let clipCGRect = CGRect(
                x: transform.clipRect.x,
                y: transform.clipRect.y,
                width: transform.clipRect.width,
                height: transform.clipRect.height
            )
            context.clip(to: clipCGRect)
        }

        let drawWidth = layout.appliedWidth * transform.scale
        let drawHeight = layout.appliedHeight * transform.scale
        let imageRect = CGRect(
            x: transform.translateX,
            y: transform.translateY,
            width: drawWidth,
            height: drawHeight
        )
        context.draw(cgImage, in: imageRect)

        context.restoreGState()
        context.endPDFPage()
    }
}
