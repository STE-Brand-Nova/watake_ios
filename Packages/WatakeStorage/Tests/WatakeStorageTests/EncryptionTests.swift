import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

@Suite("Metadata encryption")
struct EncryptionTests {
    @Test("encrypted folder metadata is not plaintext on disk")
    func metadataIsNotPlaintext() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder(name: "Very Private Folder Name")
        try await storage.saveFolder(folder)

        let resolvedRoot = try root.resolveRoot()
        let path = StorageLayout.folderMetadataFile(resolvedRoot, folder.id)
        let raw = try Data(contentsOf: path)

        #expect(!raw.isEmpty)
        #expect(String(data: raw, encoding: .utf8)?.contains("Very Private Folder Name") != true)
        #expect((try? JSONSerialization.jsonObject(with: raw)) == nil)
    }

    @Test("corrupt ciphertext produces a typed crypto error")
    func corruptCiphertextThrowsTypedError() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let resolvedRoot = try root.resolveRoot()
        let path = StorageLayout.folderMetadataFile(resolvedRoot, folder.id)
        var raw = try Data(contentsOf: path)
        raw[raw.count - 1] ^= 0xFF
        try raw.write(to: path)

        await #expect(throws: StorageError.cryptoFailure) {
            _ = try await storage.folder(id: folder.id)
        }
    }

    @Test("corrupt decrypted metadata produces a typed recovery-safe error")
    func corruptDecodedMetadataThrowsTypedError() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let resolvedRoot = try root.resolveRoot()
        let path = StorageLayout.folderMetadataFile(resolvedRoot, folder.id)

        let keyStore = KeychainEncryptionKeyStore(service: service)
        let key = try keyStore.loadOrCreateEncryptionKey()
        let garbageJSON = Data("{ \"not\": \"a folder\" }".utf8)
        let sealed = try CryptoBox.seal(garbageJSON, key: key)
        try sealed.write(to: path)

        await #expect(throws: StorageError.invalidRecord) {
            _ = try await storage.folder(id: folder.id)
        }
    }
}
