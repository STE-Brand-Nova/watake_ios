import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

@Suite("Asset store")
struct AssetStoreTests {
    @Test("asset save/read/contains/remove round trips")
    func assetRoundTrip() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let bytes = Data("scanned page bytes".utf8)
        let reference = makeAssetReference(folderId: UUID(), documentId: UUID(), bytes: bytes)

        try await storage.saveAsset(bytes, reference: reference)

        let exists = try await storage.containsAsset(reference)
        #expect(exists)

        let read = try await storage.readAsset(reference)
        #expect(read == bytes)

        try await storage.removeAsset(reference)
        let existsAfterRemoval = try await storage.containsAsset(reference)
        #expect(!existsAfterRemoval)
    }

    @Test("saving an asset with mismatched hash is rejected")
    func mismatchedHashRejected() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let bytes = Data("real bytes".utf8)
        var reference = makeAssetReference(folderId: UUID(), documentId: UUID(), bytes: bytes)
        reference = AssetReference(
            id: reference.id,
            relativePath: reference.relativePath,
            sha256Hex: String(repeating: "0", count: 64),
            byteSize: reference.byteSize,
            mediaType: reference.mediaType
        )

        await #expect(throws: StorageError.assetIntegrityMismatch) {
            try await storage.saveAsset(bytes, reference: reference)
        }
    }

    @Test("reading a missing asset throws notFound")
    func missingAssetThrows() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let reference = makeAssetReference(folderId: UUID(), documentId: UUID(), bytes: Data("missing".utf8))

        await #expect(throws: StorageError.notFound) {
            _ = try await storage.readAsset(reference)
        }
    }

    @Test("an asset tampered with on disk after writing is rejected on read")
    func tamperedOnDiskAssetRejectedOnRead() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let bytes = Data("original page bytes".utf8)
        let reference = makeAssetReference(folderId: UUID(), documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: reference)

        let resolvedRoot = try root.resolveRoot()
        let path = StorageLayout.assetFile(resolvedRoot, reference.relativePath)
        try Data("tampered replacement bytes".utf8).write(to: path)

        await #expect(throws: StorageError.assetIntegrityMismatch) {
            _ = try await storage.readAsset(reference)
        }
    }

    @Test("an asset relativePath cannot collide with an internal metadata file")
    func assetPathCannotCollideWithMetadata() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder(name: "Original Folder Name")
        try await storage.saveFolder(folder)

        let resolvedRoot = try root.resolveRoot()
        let metadataPath = StorageLayout.folderMetadataFile(resolvedRoot, folder.id)
        let metadataRelativePath = String(metadataPath.path.dropFirst(resolvedRoot.path.count + 1))

        let bytes = Data("attacker-controlled bytes".utf8)
        let collidingReference = AssetReference(
            id: UUID(),
            relativePath: metadataRelativePath,
            sha256Hex: sha256Hex(of: bytes),
            byteSize: bytes.count,
            mediaType: "application/octet-stream"
        )
        try await storage.saveAsset(bytes, reference: collidingReference)

        let assetReadBack = try await storage.readAsset(collidingReference)
        #expect(assetReadBack == bytes)

        let folderStillIntact = try await storage.folder(id: folder.id)
        #expect(folderStillIntact == folder)
    }
}
