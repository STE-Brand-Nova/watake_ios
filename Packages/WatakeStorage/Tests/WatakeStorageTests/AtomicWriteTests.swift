import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

@Suite("Atomic writes and file protection")
struct AtomicWriteTests {
    @Test("file protection is applied to the temporary file before it becomes the destination")
    func fileProtectionAppliedBeforeMove() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let recorder = RecordingFileProtectionApplier()
        let storage = makeStorage(root: root, protectionApplier: recorder, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let bytes = Data("page".utf8)
        let reference = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: reference)

        let resolvedRoot = try root.resolveRoot()
        let temporaryDirectory = StorageLayout.temporaryDirectory(resolvedRoot)

        #expect(recorder.protectedURLs.count == 2)
        #expect(recorder.protectedURLs.allSatisfy { $0.deletingLastPathComponent() == temporaryDirectory })
    }

    @Test("a failed atomic write preserves the previously stored record")
    func failedWritePreservesPriorRecord() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let recorder = RecordingFileProtectionApplier()
        let storage = makeStorage(root: root, protectionApplier: recorder, service: service)

        let folder = makeFolder(name: "Original Name")
        try await storage.saveFolder(folder)

        recorder.shouldFail = true
        let updated = makeFolder(id: folder.id, name: "Should Not Persist", createdAt: folder.createdAt)

        await #expect(throws: StorageError.self) {
            try await storage.saveFolder(updated)
        }

        recorder.shouldFail = false
        let stillOriginal = try await storage.folder(id: folder.id)
        #expect(stillOriginal?.name == "Original Name")
    }
}
