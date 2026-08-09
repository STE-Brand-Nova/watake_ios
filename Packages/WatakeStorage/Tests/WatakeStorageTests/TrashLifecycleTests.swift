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

    @Test("permanent delete preserves asset if referenced by another document")
    func permanentDeletePreservesSharedAsset() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let bytes = Data("shared".utf8)
        let asset = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: asset)

        let document1 = makeDocument(id: UUID(), folderId: folder.id, source: asset, deletedAt: Date())
        let document2 = makeDocument(id: UUID(), folderId: folder.id, source: asset, deletedAt: nil)
        try await storage.saveDocument(document1)
        try await storage.saveDocument(document2)

        try await storage.deleteDocument(id: document1.id)
        let assetStillExists = try await storage.containsAsset(asset)
        #expect(assetStillExists)
    }

    @Test("permanent folder delete throws if not trashed, then removes folder and all children")
    func permanentFolderDelete() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let bytes = Data("child".utf8)
        let asset = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: asset)
        let child = makeDocument(folderId: folder.id, source: asset, deletedAt: nil)
        try await storage.saveDocument(child)

        await #expect(throws: StorageError.folderNotInTrash) {
            try await storage.deleteFolder(id: folder.id)
        }

        let trashedFolder = Folder(
            id: folder.id,
            name: folder.name,
            colorHex: folder.colorHex,
            createdAt: folder.createdAt,
            deletedAt: Date()
        )
        try await storage.saveFolder(trashedFolder)

        try await storage.deleteFolder(id: folder.id)

        let folderExists = try await storage.folder(id: folder.id) != nil
        #expect(!folderExists)
        let childExists = try await storage.document(id: child.id) != nil
        #expect(!childExists)
        let assetExists = try await storage.containsAsset(asset)
        #expect(!assetExists)
    }

    @Test("permanent folder delete removes asset shared by multiple children in same folder")
    func permanentFolderDeleteRemovesSharedAssetInSameFolder() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let bytes = Data("shared child asset".utf8)
        let asset = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: asset)

        let doc1 = makeDocument(id: UUID(), folderId: folder.id, source: asset, deletedAt: nil)
        let doc2 = makeDocument(id: UUID(), folderId: folder.id, source: asset, deletedAt: nil)
        try await storage.saveDocument(doc1)
        try await storage.saveDocument(doc2)

        let trashedFolder = Folder(
            id: folder.id,
            name: folder.name,
            colorHex: folder.colorHex,
            createdAt: folder.createdAt,
            deletedAt: Date()
        )
        try await storage.saveFolder(trashedFolder)

        try await storage.deleteFolder(id: folder.id)

        let assetExists = try await storage.containsAsset(asset)
        #expect(!assetExists)
    }
}
