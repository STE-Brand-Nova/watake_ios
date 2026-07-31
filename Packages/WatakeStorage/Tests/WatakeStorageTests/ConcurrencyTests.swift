import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

@Suite("Concurrency")
struct ConcurrencyTests {
    @Test("concurrent saves across many folders and documents do not corrupt data")
    func concurrentWritesDoNotCorruptData() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folderIds = (0 ..< 5).map { _ in UUID() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for folderId in folderIds {
                group.addTask {
                    let folder = makeFolder(id: folderId, name: "Folder-\(folderId.uuidString.prefix(4))")
                    try await storage.saveFolder(folder)
                }
            }
            try await group.waitForAll()
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, folderId) in folderIds.enumerated() {
                group.addTask {
                    let bytes = Data("doc-\(index)".utf8)
                    let asset = makeAssetReference(folderId: folderId, documentId: UUID(), bytes: bytes)
                    try await storage.saveAsset(bytes, reference: asset)
                    let document = makeDocument(folderId: folderId, orderIndex: 0, source: asset)
                    try await storage.saveDocument(document)
                }
            }
            try await group.waitForAll()
        }

        let folders = try await storage.folders()
        #expect(folders.count == folderIds.count)

        for folderId in folderIds {
            let documents = try await storage.documents(in: folderId)
            #expect(documents.count == 1)
        }
    }

    @Test("concurrent saves to the same folder record leave a valid, decodable result")
    func concurrentWritesToSameRecordStayValid() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folderId = UUID()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0 ..< 20 {
                group.addTask {
                    let folder = makeFolder(id: folderId, name: "Name-\(index)")
                    try await storage.saveFolder(folder)
                }
            }
            try await group.waitForAll()
        }

        let final = try await storage.folder(id: folderId)
        #expect(final != nil)
        #expect(final?.name.hasPrefix("Name-") == true)
    }
}
