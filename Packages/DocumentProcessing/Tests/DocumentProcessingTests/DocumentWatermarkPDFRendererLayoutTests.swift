import CoreGraphics
import Foundation
import Testing
import WatakeDomain
@testable import DocumentProcessing

struct DocumentWatermarkPDFRendererLayoutTests {
    @Test func rejectsTiledLayoutAsUnsupported() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(50, 50)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)
        let config = makeConfig(layoutMode: .tiled, tileSpacingX: 0.35, tileSpacingY: 0.28)

        await #expect(throws: WatermarkRenderError.unsupportedLayoutMode(.tiled)) {
            try await renderer.renderPDF(for: document, watermark: config)
        }
    }
}
