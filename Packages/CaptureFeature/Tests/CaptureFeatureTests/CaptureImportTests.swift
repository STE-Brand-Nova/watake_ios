import CoreGraphics
import Foundation
import ImageIO
import Testing
import WatakeDomain
@testable import CaptureFeature

@MainActor
struct CaptureImportTests {
    @Test
    func createdFolderBecomesDestination() {
        let folder = Folder(id: UUID(), name: "New folder", colorHex: "#3B82F6", createdAt: .now)

        #expect(
            SaveDestinationView.selectionAfterCreating(folder: folder, activeFolders: [folder]) == folder.id
        )
    }

    @Test
    func saveRequiresFolder() async {
        let state = CaptureReviewState(pages: [samplePage()])
        let saver = CapturingSaver()

        await state.save(via: saver) {}

        #expect(state.saveError == "Target folder is required.")
        #expect(state.pages.count == 1)
        #expect(saver.savedPages.isEmpty)
    }

    @Test
    func photosAndFilesAdaptersPreserveBytesAndReviewMetadata() async throws {
        let imageData =
            try #require(
                Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
            )
        let photosBatch = await CaptureImportSourceAdapter.photos(data: [imageData, nil, Data("bad".utf8)])
        let filesBatch = await CaptureImportSourceAdapter.files(data: [imageData, nil, Data("bad".utf8)])

        #expect(CaptureImportSourceAdapter.maximumSelectionCount == 20)
        #expect(photosBatch.failedCount == 2)
        #expect(filesBatch.failedCount == 2)
        #expect(photosBatch.media == filesBatch.media)
        #expect(photosBatch.media.first?.data == imageData)
        #expect(photosBatch.media.first?.mediaType == "image/png")
        #expect(photosBatch.media.first?.fileExtension == "png")

        let pipeline = CaptureImportPipeline(rectifier: DeterministicRectifier())

        let photosPages = await pipeline.makePages(from: photosBatch.media)
        let filesPages = await pipeline.makePages(from: filesBatch.media)

        #expect(photosPages.count == filesPages.count)
        #expect(photosPages.first?.sourceData == filesPages.first?.sourceData)
        #expect(photosPages.first?.sourceMediaType == filesPages.first?.sourceMediaType)
        #expect(photosPages.first?.sourceFileExtension == filesPages.first?.sourceFileExtension)
        #expect(photosPages.first?.cropQuadrilateral == filesPages.first?.cropQuadrilateral)
        #expect(photosPages.first?.detectionUncertain == filesPages.first?.detectionUncertain)
    }

    @Test
    func pdfFilesRasterizeEachPageIntoPNGReviewPages() async throws {
        let pdfData = try makePDF(pageCount: 2)
        let batch = await CaptureImportSourceAdapter.files(items: [
            CaptureImportFile(data: pdfData, fileExtension: "pdf")
        ])

        #expect(batch.failedCount == 0)
        #expect(batch.media.count == 2)
        #expect(batch.media.allSatisfy { $0.mediaType == "image/png" && $0.fileExtension == "png" })
        #expect(batch.media.allSatisfy { CGImageSourceCreateWithData($0.data as CFData, nil) != nil })

        let pages = await CaptureImportPipeline(rectifier: DeterministicRectifier()).makePages(from: batch.media)
        #expect(pages.count == 2)
    }

    private func samplePage() -> CaptureReviewPage {
        CaptureReviewPage(sourceData: Data("sample".utf8))
    }

    private func makePDF(pageCount: Int) throws -> Data {
        let output = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: output as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: nil, nil))
        for index in 0 ..< pageCount {
            let mediaBox = CGRect(x: 0, y: 0, width: 180, height: 240)
            context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
            context.setFillColor(red: CGFloat(index) / CGFloat(max(1, pageCount)), green: 0.5, blue: 0.2, alpha: 1)
            context.fill(mediaBox)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }
}

private struct DeterministicRectifier: DocumentRectifying {
    func detect(in jpegData: Data) async -> RectificationResult {
        RectificationResult(quadrilateral: .unit, isDetectionConfident: false)
    }

    func rectify(jpegData: Data, quadrilateral: CropQuadrilateral, rotationDegrees: Int) async -> Data? {
        nil
    }
}

private final class CapturingSaver: CaptureSaving, @unchecked Sendable {
    var savedPages: [ImportedPage] = []

    func save(
        pages: [ImportedPage],
        grouping: GalleryGrouping,
        folderID: UUID,
        name: String
    ) async throws -> [StoredDocument] {
        savedPages = pages
        return []
    }
}
