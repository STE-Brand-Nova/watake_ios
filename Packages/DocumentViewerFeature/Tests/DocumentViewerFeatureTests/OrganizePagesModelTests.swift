import Foundation
import Testing
import WatakeDomain
@testable import DocumentViewerFeature

@MainActor
@Suite("OrganizePagesModel")
struct OrganizePagesModelTests {
    @Test("dragging changes only temporary order until Done saves once")
    func draftThenSave() async {
        let first = page(index: 0, originalIndex: 0, ocrText: "first text")
        let second = page(index: 1, originalIndex: 1, ocrText: "second text")
        let document = makeDocument(pages: [first, second])
        let store = OrganizeStore(document: document)
        let model = makeModel(document: document, store: store)

        model.move(pageID: second.id, before: first.id)

        #expect(model.pages.map(\.id) == [second.id, first.id])
        #expect(await store.saveCount == 0)

        #expect(await model.save())
        let saved = await store.document
        #expect(await store.saveCount == 1)
        #expect(saved.pages.map(\.id) == [second.id, first.id])
        #expect(saved.pages.map(\.index) == [0, 1])
        #expect(saved.pages.map(\.originalIndex) == [1, 0])
        #expect(saved.pages[0].ocrText == "second text")
    }

    @Test("forward drag inserts before target without overshooting")
    func forwardDragInsertsBeforeTarget() {
        let first = page(index: 0, originalIndex: 0)
        let second = page(index: 1, originalIndex: 1)
        let third = page(index: 2, originalIndex: 2)
        let document = makeDocument(pages: [first, second, third])
        let store = OrganizeStore(document: document)
        let model = makeModel(document: document, store: store)

        model.move(pageID: first.id, before: third.id)

        #expect(model.pages.map(\.id) == [second.id, first.id, third.id])
        #expect(model.pages.map(\.index) == [0, 1, 2])
    }

    @Test("restoring source order uses immutable original indexes")
    func restoreOriginalOrder() {
        let sourceFirst = page(index: 1, originalIndex: 0)
        let sourceSecond = page(index: 0, originalIndex: 1)
        let document = makeDocument(pages: [sourceSecond, sourceFirst])
        let store = OrganizeStore(document: document)
        let model = makeModel(document: document, store: store)

        #expect(model.canRestoreOriginalOrder)
        model.restoreOriginalOrder()

        #expect(model.pages.map(\.id) == [sourceFirst.id, sourceSecond.id])
        #expect(model.pages.map(\.index) == [0, 1])
        #expect(model.pages.map(\.originalIndex) == [0, 1])
    }

    @Test("save merges current page-scoped data instead of overwriting it")
    func savePreservesConcurrentPageData() async {
        let first = page(index: 0, originalIndex: 0)
        let second = page(index: 1, originalIndex: 1)
        let document = makeDocument(pages: [first, second])
        let store = OrganizeStore(document: document)
        let model = makeModel(document: document, store: store)
        model.move(pageID: second.id, before: first.id)

        let updatedFirst = DocumentPage(
            id: first.id,
            index: first.index,
            originalIndex: first.originalIndex,
            source: first.source,
            ocrText: "new OCR"
        )
        await store.replace(makeDocument(id: document.id, folderId: document.folderId, pages: [updatedFirst, second]))

        #expect(await model.save())
        let savedFirst = await store.document.pages.first { $0.id == first.id }
        #expect(savedFirst?.ocrText == "new OCR")
    }

    private func makeModel(document: StoredDocument, store: OrganizeStore) -> OrganizePagesModel {
        OrganizePagesModel(
            document: document,
            loadDocument: { _ in await store.document },
            saveDocument: { updated in try await store.save(updated) },
            loadThumbnail: { _ in Data() },
            onPersisted: { _ in }
        )
    }

    private func page(index: Int, originalIndex: Int, ocrText: String? = nil) -> DocumentPage {
        DocumentPage(
            id: UUID(),
            index: index,
            originalIndex: originalIndex,
            source: makeAssetReference(path: "page-\(originalIndex).bin"),
            ocrText: ocrText
        )
    }
}

private actor OrganizeStore {
    private(set) var document: StoredDocument
    private(set) var saveCount = 0

    init(document: StoredDocument) {
        self.document = document
    }

    func save(_ document: StoredDocument) throws {
        self.document = document
        saveCount += 1
    }

    func replace(_ document: StoredDocument) {
        self.document = document
    }
}
