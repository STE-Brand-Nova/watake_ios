import Foundation
import Testing
import WatakeDomain
@testable import DocumentViewerFeature

@Suite("Source vs. rectified asset selection")
struct DocumentPageDisplayAssetTests {
    @Test("prefers rectified when present")
    func prefersRectifiedWhenPresent() {
        let source = makeAssetReference()
        let rectified = makeAssetReference()
        let page = makePage(index: 0, source: source, rectified: rectified)

        #expect(page.displayAsset == rectified)
        #expect(page.isShowingRectified)
    }

    @Test("falls back to the immutable source when no rectified asset exists")
    func fallsBackToSourceWhenRectifiedMissing() {
        let source = makeAssetReference()
        let page = makePage(index: 0, source: source)

        #expect(page.displayAsset == source)
        #expect(!page.isShowingRectified)
    }

    @Test("low-confidence OCR remains detectable from persisted page data")
    func lowConfidenceOCRPersistsAcrossViewerSessions() {
        let source = makeAssetReference()
        let page = DocumentPage(
            id: UUID(),
            index: 0,
            source: source,
            ocrText: "uncertain",
            ocrBlocks: [
                OCRBlock(
                    id: UUID(),
                    text: "uncertain",
                    confidence: 0.49,
                    bounds: NormalizedRect(originX: 0, originY: 0, width: 0.5, height: 0.1)
                )
            ]
        )

        #expect(page.hasLowConfidenceOCR)
    }
}
