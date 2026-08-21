import CoreGraphics
import Foundation
import Testing
import WatakeDomain
@testable import DocumentProcessing

@Suite(.serialized)
struct DocumentWatermarkPDFRendererTests {
    @Test func rendersValidOnePagePDF() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(200, 300)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        let pdfData = try await renderer.renderPDF(for: document, watermark: makeConfig())

        let pageCount = try PDFInspection.pageCount(of: pdfData)
        #expect(pageCount == 1)
    }

    @Test func preservesMultiPageSourceOrderRegardlessOfArrayOrder() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(100, 100), (150, 150), (200, 200)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        // Shuffle the in-memory array order to prove rendering uses `index`, not array order.
        let shuffledDocument = StoredDocument(
            id: document.id,
            folderId: document.folderId,
            name: document.name,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            orderIndex: document.orderIndex,
            pages: document.pages.reversed()
        )
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        let pdfData = try await renderer.renderPDF(for: shuffledDocument, watermark: makeConfig())
        let widths = try PDFInspection.pageWidths(of: pdfData)

        #expect(widths == [100, 150, 200])
    }

    @Test func preservesPortraitOrientation() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(100, 200)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        let pdfData = try await renderer.renderPDF(for: document, watermark: makeConfig())
        let sizes = try PDFInspection.pageSizes(of: pdfData)

        #expect(sizes[0].width == 100)
        #expect(sizes[0].height == 200)
    }

    @Test func preservesLandscapeOrientation() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(200, 100)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        let pdfData = try await renderer.renderPDF(for: document, watermark: makeConfig())
        let sizes = try PDFInspection.pageSizes(of: pdfData)

        #expect(sizes[0].width == 200)
        #expect(sizes[0].height == 100)
    }

    @Test func disabledBodyProducesSourceOnlyPageWithoutError() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(100, 100)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        let config = makeConfig(body: makeTextLayer(enabled: false))
        let pdfData = try await renderer.renderPDF(for: document, watermark: config)

        #expect(try PDFInspection.pageCount(of: pdfData) == 1)
    }

    @Test func absentBodyProducesSourceOnlyPageWithoutError() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(100, 100)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        let config = makeConfig(body: nil)
        let pdfData = try await renderer.renderPDF(for: document, watermark: config)

        #expect(try PDFInspection.pageCount(of: pdfData) == 1)
    }

    @Test func rendersWithRotationAndOpacityWithoutFailure() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(300, 300)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        let config = makeConfig(
            body: makeTextLayer(rotation: 45, opacity: 0.5),
            globalRotation: -30,
            globalOpacity: 0.8
        )
        let pdfData = try await renderer.renderPDF(for: document, watermark: config)

        #expect(try PDFInspection.pageCount(of: pdfData) == 1)
    }

    @Test func sourceAssetDataIsUnchangedAfterRender() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(120, 80)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        _ = try await renderer.renderPDF(for: document, watermark: makeConfig())

        let readBack = try await store.readAsset(document.pages[0].source)
        #expect(readBack == data[0])
    }

    @Test func rejectsUndecodableSourceData() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(50, 50)])
        let document = fixture.document
        let store = fixture.store
        await store.seed(Data([0x00, 0x01, 0x02]), reference: document.pages[0].source)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        await #expect(throws: WatermarkRenderError.sourceImageUndecodable(pageIndex: 0)) {
            try await renderer.renderPDF(for: document, watermark: makeConfig())
        }
    }

    @Test func rejectsEmptySourceData() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(50, 50)])
        let document = fixture.document
        let store = fixture.store
        await store.seed(Data(), reference: document.pages[0].source)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        await #expect(throws: WatermarkRenderError.sourceImageUndecodable(pageIndex: 0)) {
            try await renderer.renderPDF(for: document, watermark: makeConfig())
        }
    }

    @Test func rejectsMissingSourceAsset() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(50, 50)])
        let document = fixture.document
        let store = fixture.store
        // Intentionally never seed the asset store.
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        await #expect(throws: WatermarkRenderError.sourceAssetUnreadable(pageIndex: 0)) {
            try await renderer.renderPDF(for: document, watermark: makeConfig())
        }
    }

    @Test func rendersEnabledHeading() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(50, 50)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)
        let config = makeConfig(heading: makeTextLayer(text: "Heading"))

        let pdf = try await renderer.renderPDF(for: document, watermark: config)
        #expect(try PDFInspection.pageCount(of: pdf) == 1)
    }

    @Test func rendersEnabledCaption() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(50, 50)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)
        let config = makeConfig(caption: makeTextLayer(text: "Caption"))

        let pdf = try await renderer.renderPDF(for: document, watermark: config)
        #expect(try PDFInspection.pageCount(of: pdf) == 1)
    }

    @Test func rendersEnabledImageLayer() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(50, 50)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)
        let logoData = SyntheticImage.makePNGData(width: 20, height: 20, red: 0, green: 0, blue: 0)
        let logoReference = SyntheticImage.makeAssetReference(pageId: UUID(), data: logoData)
        await store.seed(logoData, reference: logoReference)
        let imageLayer = WatermarkImageLayer(
            enabled: true,
            assetRef: logoReference,
            scale: 1,
            rotation: 0,
            opacity: 1,
            placement: .behindText
        )
        let config = makeConfig(image: imageLayer)

        let pdf = try await renderer.renderPDF(for: document, watermark: config)
        #expect(try PDFInspection.pageCount(of: pdf) == 1)
    }

    @Test func disabledHeadingCaptionImageDoNotTriggerUnsupportedError() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(50, 50)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)
        let config = makeConfig(
            heading: makeTextLayer(text: "Heading", enabled: false),
            caption: makeTextLayer(text: "Caption", enabled: false)
        )

        let pdfData = try await renderer.renderPDF(for: document, watermark: config)
        #expect(try PDFInspection.pageCount(of: pdfData) == 1)
    }

    @Test func unknownFontNameFallsBackInsteadOfFailing() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(100, 100)])
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)
        let config = makeConfig(body: makeTextLayer(fontName: "Definitely Not An Installed Font XYZ"))

        let pdfData = try await renderer.renderPDF(for: document, watermark: config)
        #expect(try PDFInspection.pageCount(of: pdfData) == 1)
    }

    @Test func cancellationStopsRenderingBeforeCompletion() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(50, 50), (50, 50), (50, 50)])
        let document = fixture.document
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: fixture.store)
        let signalingStore = SignalingAssetStore(inner: fixture.store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: signalingStore)

        let task = Task {
            try await renderer.renderPDF(for: document, watermark: makeConfig())
        }
        await signalingStore.firstReadStarted
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func preservesSourceImageVerticalOrientationInRenderedPDF() async throws {
        let width = 100
        let height = 100
        let topColor = SyntheticColor(red: 1, green: 0, blue: 0)
        let bottomColor = SyntheticColor(red: 0, green: 0, blue: 1)
        let pngData = SyntheticImage.makeTopBottomPNGData(
            width: width,
            height: height,
            topColor: topColor,
            bottomColor: bottomColor
        )
        let pageId = UUID()
        let reference = SyntheticImage.makeAssetReference(pageId: pageId, data: pngData)
        let store = InMemoryAssetStore()
        await store.seed(pngData, reference: reference)
        let document = StoredDocument(
            id: UUID(),
            folderId: UUID(),
            name: "Synthetic",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            orderIndex: 0,
            pages: [DocumentPage(id: pageId, index: 0, source: reference)]
        )
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        let pdfData = try await renderer.renderPDF(for: document, watermark: makeConfig(body: nil))

        let topPixel = try PDFInspection.pixelColor(of: pdfData, column: width / 2, yFromTop: 5)
        let bottomPixel = try PDFInspection.pixelColor(of: pdfData, column: width / 2, yFromTop: height - 5)

        #expect(topPixel.red > 0.5 && topPixel.blue < 0.5)
        #expect(bottomPixel.blue > 0.5 && bottomPixel.red < 0.5)
    }

    @Test func processesManyPagesSequentially() async throws {
        let pageSizes = Array(repeating: (60, 60), count: 12)
        let fixture = TestDocumentFactory.makeDocument(pageSizes: pageSizes)
        let document = fixture.document
        let store = fixture.store
        let data = fixture.pageData
        await TestDocumentFactory.seedAssets(document: document, data: data, into: store)
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        let pdfData = try await renderer.renderPDF(for: document, watermark: makeConfig())
        #expect(try PDFInspection.pageCount(of: pdfData) == 12)
    }

    @Test func invalidDocumentFailsWithDistinctError() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(100, 100)])
        let store = fixture.store
        await TestDocumentFactory.seedAssets(document: fixture.document, data: fixture.pageData, into: store)
        let invalidDocument = StoredDocument(
            id: fixture.document.id,
            folderId: fixture.document.folderId,
            name: fixture.document.name,
            createdAt: fixture.document.createdAt,
            updatedAt: fixture.document.updatedAt,
            orderIndex: -1,
            pages: fixture.document.pages
        )
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        await #expect(throws: WatermarkRenderError.invalidDocument) {
            try await renderer.renderPDF(for: invalidDocument, watermark: makeConfig())
        }
    }

    @Test func invalidWatermarkConfigFailsWithDistinctError() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(100, 100)])
        let document = fixture.document
        let store = fixture.store
        await TestDocumentFactory.seedAssets(document: document, data: fixture.pageData, into: store)
        let invalidConfig = makeConfig(body: makeTextLayer(colorHex: "not-a-color"))
        let renderer = DocumentWatermarkPDFRenderer(assetStore: store)

        await #expect(throws: WatermarkRenderError.invalidWatermarkConfig) {
            try await renderer.renderPDF(for: document, watermark: invalidConfig)
        }
    }
}
