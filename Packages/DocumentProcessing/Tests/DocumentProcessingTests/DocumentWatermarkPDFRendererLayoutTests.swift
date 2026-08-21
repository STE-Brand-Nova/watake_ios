import CoreGraphics
import Foundation
import Testing
import WatakeDomain
@testable import DocumentProcessing

@Suite(.serialized)
struct DocumentWatermarkPDFRendererLayoutTests {
    @Test func rendersTiledLayoutThroughSharedCompositor() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(50, 50)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)
        let config = makeConfig(layoutMode: .tiled, tileSpacingX: 0.35, tileSpacingY: 0.28)

        let pdf = try await renderer.renderPDF(for: document, watermark: config)
        #expect(try PDFInspection.pageCount(of: pdf) == 1)
    }
}
