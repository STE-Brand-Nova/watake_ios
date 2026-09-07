import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

@Suite("Document editing store")
struct DocumentEditingStoreTests {
    @Test("saved signatures and recovery drafts are encrypted records with explicit deletion")
    func signatureAndRecoveryRoundTrip() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let stroke = testStroke()
        let signature = SavedSignature(
            id: UUID(),
            name: "My signature",
            strokes: [stroke],
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try await storage.saveSignature(signature)
        #expect(try await storage.savedSignatures() == [signature])

        let folder = makeFolder()
        let sourceBytes = Data("source".utf8)
        let source = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: sourceBytes)
        let document = makeDocument(folderId: folder.id, source: source)
        let draft = DocumentEditRecoveryDraft(
            document: document,
            sourceDocumentID: document.id,
            selectedPageID: document.pages[0].id,
            stagedAssets: [],
            savedAt: timestamp
        )

        try await storage.saveRecoveryDraft(draft)
        #expect(try await storage.recoveryDraft(documentID: document.id) == draft)

        try await storage.deleteRecoveryDraft(documentID: document.id)
        try await storage.deleteSignature(id: signature.id)
        #expect(try await storage.recoveryDraft(documentID: document.id) == nil)
        #expect(try await storage.savedSignatures().isEmpty)
    }

    @Test("copy shares immutable assets and removing original layers preserves live copy assets")
    func copySharesAssetsAndReferenceTrackingProtectsThem() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)
        let folder = makeFolder()
        try await storage.saveFolder(folder)
        let fixture = makeAnnotatedDocument(folder: folder, imageBytes: Data("annotation image".utf8))
        try await seed(fixture, into: storage)
        let copy = makeDocumentCopy(from: fixture)
        try await storage.saveDocumentCopy(copy, sourceDocumentID: fixture.document.id)
        let clearedOriginal = removingAnnotations(from: fixture.document)
        try await storage.saveEditedDocument(clearedOriginal)

        #expect(try await storage.containsAsset(fixture.source))
        #expect(try await storage.containsAsset(fixture.image))
        #expect(try await storage.document(id: copy.id)?.pages[0].annotations[0].image == fixture.image)
    }

    @Test("removing the final image layer reclaims its staged asset")
    func removingFinalImageLayerReclaimsAsset() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)
        let folder = makeFolder()
        try await storage.saveFolder(folder)
        let fixture = makeAnnotatedDocument(folder: folder, imageBytes: Data("temporary annotation".utf8))
        try await seed(fixture, into: storage)
        let cleared = removingAnnotations(from: fixture.document)
        try await storage.saveEditedDocument(cleared)

        #expect(try await storage.containsAsset(fixture.source))
        #expect(try await !storage.containsAsset(fixture.image))
    }
}

private struct AnnotatedDocumentFixture {
    let document: StoredDocument
    let source: AssetReference
    let sourceBytes: Data
    let image: AssetReference
    let imageBytes: Data
}

private func makeAnnotatedDocument(folder: Folder, imageBytes: Data) -> AnnotatedDocumentFixture {
    let documentID = UUID()
    let sourceBytes = Data("source".utf8)
    let source = makeAssetReference(folderId: folder.id, documentId: documentID, bytes: sourceBytes)
    let image = makeAssetReference(
        folderId: folder.id,
        documentId: documentID,
        kind: "annotation-image",
        bytes: imageBytes
    )
    let annotation = PageAnnotation(
        id: UUID(),
        kind: .image,
        transform: AnnotationTransform(centerX: 0.5, centerY: 0.5, width: 0.4, height: 0.3),
        zIndex: 0,
        image: image
    )
    let page = DocumentPage(id: UUID(), index: 0, source: source, annotations: [annotation])
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let document = StoredDocument(
        id: documentID,
        folderId: folder.id,
        name: "Original",
        createdAt: timestamp,
        updatedAt: timestamp,
        orderIndex: 0,
        pages: [page]
    )
    return AnnotatedDocumentFixture(
        document: document,
        source: source,
        sourceBytes: sourceBytes,
        image: image,
        imageBytes: imageBytes
    )
}

private func seed(_ fixture: AnnotatedDocumentFixture, into storage: WatakeFileStorage) async throws {
    try await storage.saveAsset(fixture.sourceBytes, reference: fixture.source)
    try await storage.stageAnnotationAsset(fixture.imageBytes, reference: fixture.image)
    try await storage.saveDocument(fixture.document)
}

private func makeDocumentCopy(from fixture: AnnotatedDocumentFixture) -> StoredDocument {
    let annotation = fixture.document.pages[0].annotations[0]
    let copiedAnnotation = PageAnnotation(
        id: UUID(),
        kind: .image,
        transform: annotation.transform,
        zIndex: 0,
        image: fixture.image
    )
    return StoredDocument(
        id: UUID(),
        folderId: fixture.document.folderId,
        name: "Original – Copy",
        createdAt: fixture.document.createdAt,
        updatedAt: fixture.document.updatedAt,
        orderIndex: 1,
        pages: [DocumentPage(id: UUID(), index: 0, source: fixture.source, annotations: [copiedAnnotation])]
    )
}

private func removingAnnotations(from document: StoredDocument) -> StoredDocument {
    StoredDocument(
        id: document.id,
        folderId: document.folderId,
        name: document.name,
        createdAt: document.createdAt,
        updatedAt: document.updatedAt.addingTimeInterval(1),
        orderIndex: document.orderIndex,
        pages: [DocumentPage(id: document.pages[0].id, index: 0, source: document.pages[0].source)]
    )
}

private func testStroke() -> InkStroke {
    InkStroke(
        points: [
            InkPoint(location: NormalizedPoint(x: 0.1, y: 0.2)),
            InkPoint(location: NormalizedPoint(x: 0.8, y: 0.7))
        ],
        width: 0.02,
        colorHex: "#0B1220"
    )
}
