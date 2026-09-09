import Foundation
import Testing
import WatakeDomain
@testable import DocumentEditorFeature

@Suite("Document editor")
struct DocumentEditorModelTests {
    @Test @MainActor
    func addedTextKeepsEnteredContentAndStartsSelectedTextMode() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()

        model.addText("Review completed")

        #expect(model.selectedAnnotation?.text?.text == "Review completed")
        #expect(model.tool == .text)
    }

    @Test @MainActor
    func textSelectionIsExclusiveAndLeavingTextModeClearsIt() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
        model.addText("First")
        let firstID = model.selectedAnnotationID
        model.addText("Second")
        let secondID = model.selectedAnnotationID

        model.selectAnnotation(firstID)
        #expect(model.selectedAnnotationID == firstID)
        #expect(model.selectedAnnotationID != secondID)

        model.activateTool(.highlight)
        #expect(model.selectedAnnotationID == nil)
        #expect(model.tool == .highlight)
    }

    @Test @MainActor
    func textBoxCanResizeWidthAndHeightIndependentlyAsOneCommand() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
        model.addText("Resizable")

        model.beginContinuousEdit()
        model.transformSelected(width: 0.7, height: 0.2)
        model.endContinuousEdit()

        #expect(model.selectedAnnotation?.transform.width == 0.7)
        #expect(model.selectedAnnotation?.transform.height == 0.2)
        model.undo()
        #expect(model.selectedPage?.annotations.first?.transform.width == 0.58)
        #expect(model.selectedPage?.annotations.first?.transform.height == 0.12)
    }

    @Test @MainActor
    func deletingSelectedTextRemovesItAndPublishesSuccessToast() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
        model.addText("Delete me")

        model.deleteSelected()

        #expect(model.selectedPage?.annotations.isEmpty == true)
        #expect(model.selectedAnnotationID == nil)
        #expect(model.toastMessage == "Text deleted")
        let revision = model.toastRevision
        model.clearToast(revision: revision)
        #expect(model.toastMessage == nil)
    }

    @Test
    func textInteractionPreviewUsesStablePageRelativeGeometry() {
        let start = AnnotationTransform(centerX: 0.4, centerY: 0.3, width: 0.2, height: 0.1)
        let moved = DocumentAnnotationInteraction.moved(
            from: start,
            translation: CGSize(width: 50, height: 100),
            pageSize: CGSize(width: 500, height: 1000)
        )
        let resized = DocumentAnnotationInteraction.resized(
            from: start,
            translation: CGSize(width: 100, height: 200),
            pageSize: CGSize(width: 500, height: 1000)
        )

        #expect(abs(moved.centerX - 0.5) < 0.000_001)
        #expect(abs(moved.centerY - 0.4) < 0.000_001)
        #expect(abs(resized.width - 0.4) < 0.000_001)
        #expect(abs(resized.height - 0.3) < 0.000_001)
        #expect(abs(resized.centerX - 0.5) < 0.000_001)
        #expect(abs(resized.centerY - 0.4) < 0.000_001)
    }

    @Test
    func textPaletteIncludesWhite() {
        #expect(DocumentEditorPalette.textColors.contains("#FFFFFF"))
    }

    @Test @MainActor
    func historyIsIndependentForEveryPage() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
        model.addText()
        let firstPageID = model.selectedPageID
        model.selectPage(fixture.secondPageID)
        model.addText()
        model.undo()
        #expect(model.selectedPage?.annotations.isEmpty == true)
        model.selectPage(firstPageID)
        #expect(model.selectedPage?.annotations.count == 1)
        #expect(model.canUndo)
    }

    @Test @MainActor
    func donePreservesDocumentPageAndSourceIdentity() async {
        let fixture = EditorFixture()
        let (model, store) = fixture.makeModel()
        let originalPageIDs = model.pages.map(\.id)
        let originalSources = model.pages.map(\.source)
        model.addText()
        #expect(await model.save())
        let saved = await store.currentDocument()
        #expect(saved.id == fixture.documentID)
        #expect(saved.pages.map(\.id) == originalPageIDs)
        #expect(saved.pages.map(\.source) == originalSources)
        #expect(saved.pages[0].annotations.count == 1)
        #expect(!model.isDirty)
    }

    @Test @MainActor
    func saveCopyUsesFreshIdentityAndSharedImmutableAssets() async {
        let fixture = EditorFixture()
        let (model, store) = fixture.makeModel()
        model.addText()
        let sourceReferences = model.pages.map(\.source)
        let sourcePageIDs = Set(model.pages.map(\.id))
        let sourceAnnotationIDs = Set(model.pages.flatMap(\.annotations).map(\.id))
        #expect(await model.saveCopy(name: "Document – Copy", folderID: fixture.folderID))
        let copy = await store.currentDocument()
        #expect(copy.id != fixture.documentID)
        #expect(Set(copy.pages.map(\.id)).isDisjoint(with: sourcePageIDs))
        #expect(Set(copy.pages.flatMap(\.annotations).map(\.id)).isDisjoint(with: sourceAnnotationIDs))
        #expect(copy.pages.map(\.source) == sourceReferences)
        #expect(copy.tagIds == fixture.tagIDs)
        #expect(model.sourceDocumentID == copy.id)
    }

    @Test @MainActor
    func editWritesRecoveryBoundaryAfterDebounce() async throws {
        let fixture = EditorFixture()
        let (model, store) = fixture.makeModel()
        model.addText()
        try await Task.sleep(for: .milliseconds(700))
        let recovery = await store.currentRecovery()
        #expect(recovery?.sourceDocumentID == fixture.documentID)
        #expect(recovery?.document.pages[0].annotations.count == 1)
    }

    @Test @MainActor
    func failedSaveKeepsDraftOpenAndRetryCommitsIt() async {
        let fixture = EditorFixture()
        let (model, store) = fixture.makeModel()
        model.addText()
        await store.failNextEditedSave()

        #expect(await !(model.save()))
        #expect(model.isDirty)
        #expect(model.saveState == .failed)

        #expect(await model.save())
        #expect(!model.isDirty)
        #expect(await store.currentDocument().pages[0].annotations.count == 1)
    }

    @Test @MainActor
    func successfulSaveRemovesUnusedStagedImages() async {
        let fixture = EditorFixture()
        let (model, store) = fixture.makeModel()
        #expect(await model.importImage(data: Data("image".utf8), mediaType: "image/png", fileExtension: "png"))
        model.deleteSelected()

        #expect(await model.save())
        #expect(await store.discardedAssetCount() == 1)
    }

    @Test @MainActor
    func successfulSaveCannotBeFollowedByAStaleDebouncedRecoveryWrite() async throws {
        let fixture = EditorFixture()
        let (model, store) = fixture.makeModel()
        model.addText()

        #expect(await model.save())
        try await Task.sleep(for: .milliseconds(700))

        #expect(await store.currentRecovery() == nil)
    }
}

private final class EditorFixture: @unchecked Sendable {
    let folderID = UUID()
    let documentID = UUID()
    let firstPageID = UUID()
    let secondPageID = UUID()
    let tagIDs = [UUID()]
    let firstAsset = AssetReference(
        id: UUID(), relativePath: "source-1.jpg", sha256Hex: String(repeating: "a", count: 64),
        byteSize: 1, mediaType: "image/jpeg"
    )
    let secondAsset = AssetReference(
        id: UUID(), relativePath: "source-2.jpg", sha256Hex: String(repeating: "b", count: 64),
        byteSize: 1, mediaType: "image/jpeg"
    )

    @MainActor func makeModel() -> (DocumentEditorModel, MemoryEditorStore) {
        let timestamp = Date(timeIntervalSince1970: 1000)
        let document = StoredDocument(
            id: documentID, folderId: folderID, name: "Document", createdAt: timestamp,
            updatedAt: timestamp, orderIndex: 0,
            pages: [
                DocumentPage(id: firstPageID, index: 0, source: firstAsset, ocrText: "Page one"),
                DocumentPage(id: secondPageID, index: 1, source: secondAsset, ocrText: "Page two")
            ], tagIds: tagIDs
        )
        let folder = Folder(id: folderID, name: "Folder", colorHex: "#1F4FEB", createdAt: timestamp)
        let store = MemoryEditorStore(document: document, folder: folder)
        return (DocumentEditorModel(document: document, store: store), store)
    }
}

private actor MemoryEditorStore: DocumentEditingStore {
    private var storedDocument: StoredDocument
    private let folder: Folder
    private var recovery: DocumentEditRecoveryDraft?
    private var shouldFailEditedSave = false
    private var discardedAssets: [AssetReference] = []
    init(document: StoredDocument, folder: Folder) {
        storedDocument = document
        self.folder = folder
    }

    func currentDocument() -> StoredDocument {
        storedDocument
    }

    func currentRecovery() -> DocumentEditRecoveryDraft? {
        recovery
    }

    func failNextEditedSave() {
        shouldFailEditedSave = true
    }

    func discardedAssetCount() -> Int {
        discardedAssets.count
    }

    func document(id: UUID) -> StoredDocument? {
        id == storedDocument.id ? storedDocument : nil
    }

    func folders() -> [Folder] {
        [folder]
    }

    func documents(in _: UUID) -> [StoredDocument] {
        [storedDocument]
    }

    func readAsset(_: AssetReference) throws -> Data {
        Data([0])
    }

    func stageAnnotationAsset(_: Data, reference _: AssetReference) {}
    func discardAnnotationAssets(_ references: [AssetReference]) {
        discardedAssets.append(contentsOf: references)
    }

    func saveEditedDocument(_ document: StoredDocument) throws {
        if shouldFailEditedSave {
            shouldFailEditedSave = false
            throw MemoryEditorStoreError.saveFailed
        }
        storedDocument = document
    }

    func saveDocumentCopy(_ document: StoredDocument, sourceDocumentID _: UUID) {
        storedDocument = document
    }

    func savedSignatures() -> [SavedSignature] {
        []
    }

    func saveSignature(_: SavedSignature) {}
    func deleteSignature(id _: UUID) {}
    func recoveryDraft(documentID _: UUID) -> DocumentEditRecoveryDraft? {
        recovery
    }

    func saveRecoveryDraft(_ draft: DocumentEditRecoveryDraft) {
        recovery = draft
    }

    func deleteRecoveryDraft(documentID _: UUID) {
        recovery = nil
    }
}

private enum MemoryEditorStoreError: Error {
    case saveFailed
}
