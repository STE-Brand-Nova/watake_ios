import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

@Suite("Move document between folders")
struct MoveDocumentTests {
    @Test("move preserves id, pages, assets, tags, and creation date, and is durable across reload")
    func movePreservesDocumentIdentity() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let source = makeFolder(name: "Source")
        let destination = makeFolder(name: "Destination")
        try await storage.saveFolder(source)
        try await storage.saveFolder(destination)

        let bytes = Data("page".utf8)
        let asset = makeAssetReference(folderId: source.id, documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: asset)
        let original = makeDocument(folderId: source.id, name: "Diploma", source: asset)
        try await storage.saveDocument(original)

        let moved = StoredDocument(
            id: original.id,
            folderId: destination.id,
            name: original.name,
            createdAt: original.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_900),
            orderIndex: 0,
            pages: original.pages,
            tagIds: original.tagIds
        )
        try await storage.moveDocument(moved)

        let reloaded = try #require(try await storage.document(id: original.id))
        #expect(reloaded.id == original.id)
        #expect(reloaded.folderId == destination.id)
        #expect(reloaded.pages == original.pages)
        #expect(reloaded.tagIds == original.tagIds)
        #expect(reloaded.createdAt == original.createdAt)

        let sourceDocuments = try await storage.documents(in: source.id)
        #expect(sourceDocuments.isEmpty)
        let destinationDocuments = try await storage.documents(in: destination.id)
        #expect(destinationDocuments.map(\.id) == [original.id])

        let assetStillReadable = try await storage.readAsset(asset)
        #expect(assetStillReadable == bytes)
    }

    @Test("move rejects a destination folder that is in Trash")
    func moveRejectsTrashedDestination() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let source = makeFolder(name: "Source")
        let trashedDestination = makeFolder(name: "Trashed", deletedAt: Date(timeIntervalSince1970: 1_700_000_500))
        try await storage.saveFolder(source)
        try await storage.saveFolder(trashedDestination)

        let bytes = Data("page".utf8)
        let asset = makeAssetReference(folderId: source.id, documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: asset)
        let original = makeDocument(folderId: source.id, source: asset)
        try await storage.saveDocument(original)

        let attempted = StoredDocument(
            id: original.id,
            folderId: trashedDestination.id,
            name: original.name,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt,
            orderIndex: 0,
            pages: original.pages
        )
        await #expect(throws: StorageError.owningFolderUnavailable) {
            try await storage.moveDocument(attempted)
        }
    }

    @Test("moved document can be trashed and restored, ending up in the destination folder")
    func movedThenTrashedThenRestoredStaysInDestination() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let source = makeFolder(name: "Source")
        let destination = makeFolder(name: "Destination")
        try await storage.saveFolder(source)
        try await storage.saveFolder(destination)

        let bytes = Data("page".utf8)
        let asset = makeAssetReference(folderId: source.id, documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: asset)
        let original = makeDocument(folderId: source.id, source: asset)
        try await storage.saveDocument(original)

        let moved = StoredDocument(
            id: original.id, folderId: destination.id, name: original.name,
            createdAt: original.createdAt, updatedAt: original.updatedAt, orderIndex: 0, pages: original.pages
        )
        try await storage.moveDocument(moved)

        let trashed = StoredDocument(
            id: original.id, folderId: destination.id, name: original.name,
            createdAt: original.createdAt, updatedAt: original.updatedAt, orderIndex: 0, pages: original.pages,
            deletedAt: Date(timeIntervalSince1970: 1_700_001_000)
        )
        try await storage.saveDocument(trashed)
        let afterTrash = try #require(try await storage.document(id: original.id))
        #expect(afterTrash.folderId == destination.id)
        #expect(afterTrash.deletedAt != nil)

        let restored = StoredDocument(
            id: original.id, folderId: destination.id, name: original.name,
            createdAt: original.createdAt, updatedAt: original.updatedAt, orderIndex: 0, pages: original.pages
        )
        try await storage.saveDocument(restored)
        let afterRestore = try #require(try await storage.document(id: original.id))
        #expect(afterRestore.folderId == destination.id)
        #expect(afterRestore.deletedAt == nil)
    }

    @Test("a crash between the directory rename and the folderId rewrite self-heals, durably, on the next read")
    func crashBetweenRenameAndFolderIdRewriteSelfHeals() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let source = makeFolder(name: "Source")
        let destination = makeFolder(name: "Destination")
        try await storage.saveFolder(source)
        try await storage.saveFolder(destination)

        let bytes = Data("page".utf8)
        let asset = makeAssetReference(folderId: source.id, documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: asset)
        let original = makeDocument(folderId: source.id, source: asset)
        try await storage.saveDocument(original)

        // Forge exactly the on-disk state `moveDocument` leaves behind if the
        // process is killed after its atomic directory rename but before it
        // rewrites `document.json.enc` with the corrected `folderId`: the
        // metadata directory (with its stale, still-source-folder content)
        // is physically relocated by hand, bypassing `moveDocument` entirely.
        let rootURL = root.root
        let oldDirectory = StorageLayout.documentDirectory(rootURL, source.id, original.id)
        let newDirectory = StorageLayout.documentDirectory(rootURL, destination.id, original.id)
        try FileManager.default.createDirectory(
            at: StorageLayout.documentsRoot(rootURL, destination.id), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: oldDirectory, to: newDirectory)

        let healed = try #require(try await storage.document(id: original.id))
        #expect(healed.folderId == destination.id)
        #expect(healed.pages == original.pages)
        let sourceDocuments = try await storage.documents(in: source.id)
        #expect(sourceDocuments.isEmpty)
        let destinationDocuments = try await storage.documents(in: destination.id)
        #expect(destinationDocuments.map(\.id) == [original.id])

        // The correction must be written back to disk, not just returned for
        // this call: a fresh storage instance over the same root (simulating
        // a relaunch) must see the corrected `folderId` without needing to
        // re-run the heal.
        let reopened = makeStorage(root: root, service: service)
        let reloaded = try #require(try await reopened.document(id: original.id))
        #expect(reloaded.folderId == destination.id)
    }
}
