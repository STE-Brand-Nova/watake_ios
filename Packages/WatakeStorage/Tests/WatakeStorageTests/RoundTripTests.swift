import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

@Suite("Folder and document round trips")
struct RoundTripTests {
    @Test("folder create/read/update round trips")
    func folderRoundTrip() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder(name: "Original")
        try await storage.saveFolder(folder)

        let fetched = try await storage.folder(id: folder.id)
        #expect(fetched == folder)

        let updated = makeFolder(id: folder.id, name: "Renamed", createdAt: folder.createdAt)
        try await storage.saveFolder(updated)

        let refetched = try await storage.folder(id: folder.id)
        #expect(refetched?.name == "Renamed")

        let list = try await storage.folders()
        #expect(list.map(\.id) == [folder.id])
    }

    @Test("document create/read/update round trips and orders by orderIndex")
    func documentRoundTrip() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let bytesA = Data("a".utf8)
        let assetA = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: bytesA)
        try await storage.saveAsset(bytesA, reference: assetA)
        let documentA = makeDocument(folderId: folder.id, orderIndex: 1, source: assetA)
        try await storage.saveDocument(documentA)

        let bytesB = Data("b".utf8)
        let assetB = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: bytesB)
        try await storage.saveAsset(bytesB, reference: assetB)
        let documentB = makeDocument(folderId: folder.id, orderIndex: 0, source: assetB)
        try await storage.saveDocument(documentB)

        let listed = try await storage.documents(in: folder.id)
        #expect(listed.map(\.id) == [documentB.id, documentA.id])

        let updated = makeDocument(
            id: documentA.id,
            folderId: folder.id,
            name: "Renamed",
            orderIndex: 1,
            source: assetA
        )
        try await storage.saveDocument(updated)

        let fetched = try await storage.document(id: documentA.id)
        #expect(fetched?.name == "Renamed")
    }

    @Test("tag and watermark preset round trip")
    func tagAndPresetRoundTrip() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let tag = Tag(id: UUID(), label: "Urgent", colorHex: "#ff0000")
        try await storage.saveTag(tag)
        let tags = try await storage.tags()
        #expect(tags == [tag])

        let config = WatermarkConfig(
            automatic: true,
            globalPosition: .center,
            globalRotation: 0,
            globalOpacity: 0.5
        )
        let preset = WatermarkPreset(
            id: UUID(),
            name: "Company A",
            config: config,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await storage.saveWatermarkPreset(preset)
        let presets = try await storage.watermarkPresets()
        #expect(presets == [preset])
    }

    @Test("reassigning a document to a different folder is rejected")
    func folderReassignmentRejected() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folderA = makeFolder()
        let folderB = makeFolder()
        try await storage.saveFolder(folderA)
        try await storage.saveFolder(folderB)

        let bytes = Data("a".utf8)
        let asset = makeAssetReference(folderId: folderA.id, documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: asset)
        let document = makeDocument(folderId: folderA.id, source: asset)
        try await storage.saveDocument(document)

        let moved = makeDocument(id: document.id, folderId: folderB.id, source: asset)

        await #expect(throws: StorageError.folderReassignmentUnsupported) {
            try await storage.saveDocument(moved)
        }
    }

    @Test("saving a document into a folder that does not exist is rejected")
    func documentRequiresExistingFolder() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let missingFolderId = UUID()
        let asset = makeAssetReference(folderId: missingFolderId, documentId: UUID(), bytes: Data("a".utf8))
        let document = makeDocument(folderId: missingFolderId, source: asset)

        await #expect(throws: StorageError.owningFolderUnavailable) {
            try await storage.saveDocument(document)
        }
    }

    @Test("saving a document into a trashed folder is rejected")
    func documentRequiresNonTrashedFolder() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let trashedFolder = makeFolder(deletedAt: Date(timeIntervalSince1970: 1_700_000_500))
        try await storage.saveFolder(trashedFolder)

        let asset = makeAssetReference(folderId: trashedFolder.id, documentId: UUID(), bytes: Data("a".utf8))
        let document = makeDocument(folderId: trashedFolder.id, source: asset)

        await #expect(throws: StorageError.owningFolderUnavailable) {
            try await storage.saveDocument(document)
        }
    }

    @Test("saving a document whose page source asset was never written is rejected")
    func documentRequiresExistingSourceAsset() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let neverSavedAsset = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: Data("a".utf8))
        let document = makeDocument(folderId: folder.id, source: neverSavedAsset)

        await #expect(throws: StorageError.notFound) {
            try await storage.saveDocument(document)
        }

        let stored = try await storage.document(id: document.id)
        #expect(stored == nil)
    }
}
