import Foundation
import Testing
import WatakeDomain
@testable import DocumentViewerFeature

@MainActor
@Suite("Document viewer OCR")
struct DocumentViewerOCRModelTests {
    @Test("extracting shows progress then persists complete text")
    func extractionPersistsCompleteText() async throws {
        let source = makeAssetReference()
        let page = makePage(index: 0, source: source)
        let document = makeDocument(pages: [page])
        let store = FakeOCRStore()
        await store.seed(document: document, assets: [source.id: Data("page".utf8)])
        let recognizer = FakeOCRRecognizer()
        let persistenceRecorder = OCRPersistenceRecorder()
        await recognizer.setDelay(nanoseconds: 100_000_000)
        await recognizer.setResults([result(text: "synthetic text")])

        let model = DocumentViewerModel(
            documentID: document.id,
            loader: store,
            thumbnailLoader: FakeThumbnailLoader(),
            ocrRecognizer: recognizer,
            ocrStore: store,
            onOCRPersisted: { document in persistenceRecorder.record(document) }
        )
        model.load()
        await model.waitUntilIdle()
        model.extractText()

        #expect(model.ocrState == .extracting(completedPages: 0, totalPages: 0))
        await model.waitUntilOCRIdle()

        #expect(model.ocrState == .completed(lowConfidence: false))
        #expect(await store.saveCount == 1)
        #expect(persistenceRecorder.documents.map(\.id) == [document.id])
        let stored = try #require(await store.document(id: document.id))
        #expect(stored.pages[0].ocrText == "synthetic text")
    }

    @Test("cancellation prevents persistence")
    func cancellationPreventsPersistence() async {
        let source = makeAssetReference()
        let document = makeDocument(pages: [makePage(index: 0, source: source)])
        let store = FakeOCRStore()
        await store.seed(document: document, assets: [source.id: Data("page".utf8)])
        let recognizer = FakeOCRRecognizer()
        await recognizer.setDelay(nanoseconds: 200_000_000)
        await recognizer.setResults([result(text: "synthetic text")])
        let model = DocumentViewerModel(
            documentID: document.id,
            loader: store,
            thumbnailLoader: FakeThumbnailLoader(),
            ocrRecognizer: recognizer,
            ocrStore: store
        )
        model.load()
        await model.waitUntilIdle()
        model.extractText()
        model.cancelTextExtraction()
        await model.waitUntilOCRIdle()

        #expect(model.ocrState == .cancelled)
        #expect(await store.saveCount == 0)
    }

    @Test("late result from a non-cooperative recognizer cannot persist after cancellation")
    func nonCooperativeCancellationPreventsPersistence() async {
        let source = makeAssetReference()
        let document = makeDocument(pages: [makePage(index: 0, source: source)])
        let store = FakeOCRStore()
        await store.seed(document: document, assets: [source.id: Data("page".utf8)])
        let recognizer = NonCooperativeOCRRecognizer()
        let model = DocumentViewerModel(
            documentID: document.id,
            loader: store,
            thumbnailLoader: FakeThumbnailLoader(),
            ocrRecognizer: recognizer,
            ocrStore: store
        )
        model.load()
        await model.waitUntilIdle()
        model.extractText()
        await recognizer.started
        model.cancelTextExtraction()
        await recognizer.finish(with: result(text: "synthetic text"))
        await model.waitUntilOCRIdle()

        #expect(model.ocrState == .cancelled)
        #expect(await store.saveCount == 0)
    }

    @Test("cancellation during an already-pending save reports completed after commit")
    func cancellationDuringPersistenceReportsCompletion() async {
        let source = makeAssetReference()
        let document = makeDocument(pages: [makePage(index: 0, source: source)])
        let store = FakeOCRStore()
        await store.seed(document: document, assets: [source.id: Data("page".utf8)])
        await store.suspendNextSave()
        let recognizer = FakeOCRRecognizer()
        await recognizer.setResults([result(text: "synthetic text")])
        let model = DocumentViewerModel(
            documentID: document.id,
            loader: store,
            thumbnailLoader: FakeThumbnailLoader(),
            ocrRecognizer: recognizer,
            ocrStore: store
        )
        model.load()
        await model.waitUntilIdle()
        model.extractText()
        await store.saveStarted
        model.cancelTextExtraction()
        await store.finishSave()
        await model.waitUntilOCRIdle()

        #expect(model.ocrState == .completed(lowConfidence: false))
        #expect(await store.saveCount == 1)
    }

    @Test("no text does not persist an empty overwrite")
    func noTextDoesNotPersist() async {
        let source = makeAssetReference()
        let document = makeDocument(pages: [makePage(index: 0, source: source)])
        let store = FakeOCRStore()
        await store.seed(document: document, assets: [source.id: Data("page".utf8)])
        let recognizer = FakeOCRRecognizer()
        await recognizer.setResults([OCRRecognitionResult(text: "", blocks: [])])
        let model = DocumentViewerModel(
            documentID: document.id,
            loader: store,
            thumbnailLoader: FakeThumbnailLoader(),
            ocrRecognizer: recognizer,
            ocrStore: store
        )
        model.load()
        await model.waitUntilIdle()
        model.extractText()
        await model.waitUntilOCRIdle()

        #expect(model.ocrState == .noText)
        #expect(await store.saveCount == 0)
    }

    @Test("recognition failure never persists")
    func failureDoesNotPersist() async {
        let source = makeAssetReference()
        let document = makeDocument(pages: [makePage(index: 0, source: source)])
        let store = FakeOCRStore()
        await store.seed(document: document, assets: [source.id: Data("page".utf8)])
        let recognizer = FakeOCRRecognizer()
        await recognizer.setFailure(true)
        let model = DocumentViewerModel(
            documentID: document.id,
            loader: store,
            thumbnailLoader: FakeThumbnailLoader(),
            ocrRecognizer: recognizer,
            ocrStore: store
        )
        model.load()
        await model.waitUntilIdle()
        model.extractText()
        await model.waitUntilOCRIdle()

        #expect(model.ocrState == .failure)
        #expect(await store.saveCount == 0)
    }

    private func result(text: String, confidence: Double = 0.9) -> OCRRecognitionResult {
        OCRRecognitionResult(
            text: text,
            blocks: [
                OCRBlock(
                    id: UUID(),
                    text: text,
                    confidence: confidence,
                    bounds: NormalizedRect(originX: 0.1, originY: 0.2, width: 0.3, height: 0.1)
                )
            ]
        )
    }
}
