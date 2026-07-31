import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

@Suite("Startup cleanup")
struct CleanupTests {
    @Test("cleanup removes stale files from the dedicated temp directory but preserves real records")
    func cleanupRemovesOnlyDedicatedTemporaryFiles() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let resolvedRoot = try root.resolveRoot()
        let temporaryDirectory = StorageLayout.temporaryDirectory(resolvedRoot)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let staleTemp = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("stale".utf8).write(to: staleTemp)

        try await storage.prepare()

        #expect(!FileManager.default.fileExists(atPath: staleTemp.path))
        let stillThere = try await storage.folder(id: folder.id)
        #expect(stillThere == folder)
    }

    @Test("cleanup never touches real asset files even if their name looks like a temp file")
    func cleanupDoesNotTouchLookalikeAssetNames() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let bytes = Data("page bytes".utf8)
        let lookalikeReference = AssetReference(
            id: UUID(),
            relativePath: ".\(UUID().uuidString).watake-tmp",
            sha256Hex: sha256Hex(of: bytes),
            byteSize: bytes.count,
            mediaType: "application/octet-stream"
        )
        try await storage.saveAsset(bytes, reference: lookalikeReference)

        try await storage.prepare()

        let stillReadable = try await storage.readAsset(lookalikeReference)
        #expect(stillReadable == bytes)
    }
}
