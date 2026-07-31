import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

@Suite("Document trash lifecycle")
struct TrashLifecycleTests {
    @Test("permanent delete is rejected until the document is soft-deleted, then removes it")
    func softDeleteRestoreAndPermanentDelete() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let bytes = Data("d".utf8)
        let asset = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: asset)
        let document = makeDocument(folderId: folder.id, source: asset)
        try await storage.saveDocument(document)

        await #expect(throws: StorageError.documentNotInTrash) {
            try await storage.deleteDocument(id: document.id)
        }

        let softDeleted = makeDocument(
            id: document.id,
            folderId: folder.id,
            source: asset,
            deletedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        try await storage.saveDocument(softDeleted)

        let trashed = try await storage.document(id: document.id)
        #expect(trashed?.deletedAt != nil)

        let restored = makeDocument(id: document.id, folderId: folder.id, source: asset, deletedAt: nil)
        try await storage.saveDocument(restored)
        let afterRestore = try await storage.document(id: document.id)
        #expect(afterRestore?.deletedAt == nil)

        try await storage.saveDocument(softDeleted)
        try await storage.deleteDocument(id: document.id)

        let afterPermanentDelete = try await storage.document(id: document.id)
        #expect(afterPermanentDelete == nil)
    }

    @Test("permanent delete removes the document's source and rectified assets, not just metadata")
    func permanentDeleteRemovesAssets() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let documentId = UUID()
        let pageId = UUID()
        let sourceBytes = Data("source page".utf8)
        let sourceAsset = makeAssetReference(folderId: folder.id, documentId: documentId, pageId: pageId, bytes: sourceBytes)
        try await storage.saveAsset(sourceBytes, reference: sourceAsset)

        let rectifiedBytes = Data("rectified page".utf8)
        let rectifiedAsset = makeAssetReference(
            folderId: folder.id,
            documentId: documentId,
            pageId: pageId,
            kind: "rectified",
            bytes: rectifiedBytes
        )
        try await storage.saveAsset(rectifiedBytes, reference: rectifiedAsset)

        let page = DocumentPage(id: UUID(), index: 0, source: sourceAsset, rectified: rectifiedAsset)
        let document = StoredDocument(
            id: documentId,
            folderId: folder.id,
            name: "Diploma",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            orderIndex: 0,
            pages: [page]
        )
        try await storage.saveDocument(document)

        let trashed = StoredDocument(
            id: document.id,
            folderId: folder.id,
            name: document.name,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            orderIndex: document.orderIndex,
            pages: [page],
            deletedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        try await storage.saveDocument(trashed)

        try await storage.deleteDocument(id: document.id)

        let sourceStillExists = try await storage.containsAsset(sourceAsset)
        let rectifiedStillExists = try await storage.containsAsset(rectifiedAsset)
        #expect(!sourceStillExists)
        #expect(!rectifiedStillExists)
    }

    @Test("permanent delete of an unknown document throws notFound")
    func permanentDeleteUnknownDocumentThrows() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        await #expect(throws: StorageError.notFound) {
            try await storage.deleteDocument(id: UUID())
        }
    }
}
