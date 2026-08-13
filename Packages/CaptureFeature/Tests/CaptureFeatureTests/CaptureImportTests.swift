import Foundation
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

    private func samplePage() -> CaptureReviewPage {
        CaptureReviewPage(sourceData: Data("sample".utf8))
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
