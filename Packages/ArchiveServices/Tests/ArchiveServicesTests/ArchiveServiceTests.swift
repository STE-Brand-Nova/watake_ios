import CryptoKit
import Foundation
import Security
import Testing
import WatakeDomain
import WatakeStorage
@testable import ArchiveServices

struct ArchiveServiceTests {
    @Test func renameAndStableReorderPersist() async throws {
        let folder = makeFolder()
        let first = makeDocument(folder: folder, order: 0)
        let second = makeDocument(folder: folder, order: 1)
        let repository = MemoryRepository(folder: folder, documents: [first, second])
        let service = ArchiveService(repository: repository, now: { Date(timeIntervalSince1970: 1_700_001_000) })

        let renamed = try await service.rename(documentId: first.id, to: "Final transcript")
        #expect(renamed.name == "Final transcript")
        try await service.reorderDocuments(in: folder.id, ids: [second.id, first.id])
        let ordered = try await repository.documents(in: folder.id)
        #expect(ordered.map(\.id) == [second.id, first.id])
        #expect(ordered.map(\.orderIndex) == [0, 1])
    }

    @Test func assignsSeveralTags() async throws {
        let folder = makeFolder()
        let document = makeDocument(folder: folder, order: 0)
        let red = WatakeDomain.Tag(id: UUID(), label: "Work", colorHex: ArchiveTagPalette.colors[0])
        let blue = WatakeDomain.Tag(id: UUID(), label: "2026", colorHex: ArchiveTagPalette.colors[8])
        let repository = MemoryRepository(folder: folder, documents: [document], tags: [red, blue])
        let service = ArchiveService(repository: repository)

        let updated = try await service.assign(tagIds: [red.id, blue.id], to: document.id)
        #expect(Set(updated.tagIds) == Set([red.id, blue.id]))
    }

    @Test func trashRestoreKeepsOriginalFolderAndRetention() async throws {
        let folder = makeFolder()
        let document = makeDocument(folder: folder, order: 0)
        let timestamp = Date(timeIntervalSince1970: 1_700_001_000)
        let repository = MemoryRepository(folder: folder, documents: [document])
        let service = ArchiveService(repository: repository, now: { timestamp })

        try await service.moveToTrash(documentId: document.id)
        let candidate = try await repository.document(id: document.id)
        let trashed = try #require(candidate)
        #expect(trashed.folderId == folder.id)
        #expect(ArchiveService.retentionDaysRemaining(deletedAt: timestamp, now: timestamp) == 30)
        try await service.restore(documentId: document.id)
        #expect(try await repository.document(id: document.id)?.deletedAt == nil)
    }

    @Test func folderTrashWorksWithFileStorageAndKeepsIndependentTombstones() async throws {
        let root = TestStorageRoot()
        defer { try? FileManager.default.removeItem(at: root.url) }
        let serviceName = "archive-services-tests.\(UUID().uuidString)"
        defer { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: serviceName] as CFDictionary) }
        let storage = WatakeFileStorage(
            rootResolver: root,
            protectionApplier: UntilFirstUnlockFileProtection(),
            encryptionKeyStore: KeychainEncryptionKeyStore(service: serviceName)
        )
        let folder = makeFolder()
        let bytes = Data("page".utf8)
        let reference = AssetReference(
            id: UUID(),
            relativePath: "documents/\(UUID().uuidString.lowercased())/source/page.jpg",
            sha256Hex: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteSize: bytes.count,
            mediaType: "image/jpeg"
        )
        try await storage.saveFolder(folder)
        try await storage.saveAsset(bytes, reference: reference)
        let document = StoredDocument(
            id: UUID(), folderId: folder.id, name: "Scan", createdAt: folder.createdAt, updatedAt: folder.createdAt,
            orderIndex: 0, pages: [DocumentPage(id: UUID(), index: 0, source: reference)]
        )
        try await storage.saveDocument(document)
        let archive = ArchiveService(repository: storage)

        try await archive.moveToTrash(documentId: document.id)
        try await archive.moveToTrash(folderId: folder.id)
        try await archive.restore(folderId: folder.id)

        #expect(try await storage.folder(id: folder.id)?.deletedAt == nil)
        #expect(try await storage.document(id: document.id)?.deletedAt != nil)
    }
}

private actor MemoryRepository: DocumentRepository {
    private var folderValues: [UUID: Folder]
    private var documentValues: [UUID: StoredDocument]
    private var tagValues: [UUID: WatakeDomain.Tag]

    init(folder: Folder, documents: [StoredDocument], tags: [WatakeDomain.Tag] = []) {
        folderValues = [folder.id: folder]
        documentValues = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        tagValues = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
    }

    func folder(id: UUID) async throws -> Folder? {
        folderValues[id]
    }

    func folders() async throws -> [Folder] {
        Array(folderValues.values)
    }

    func saveFolder(_ folder: Folder) async throws {
        folderValues[folder.id] = folder
    }

    func document(id: UUID) async throws -> StoredDocument? {
        documentValues[id]
    }

    func documents(in folderId: UUID) async throws -> [StoredDocument] {
        documentValues.values.filter { $0.folderId == folderId }.sorted { $0.orderIndex < $1.orderIndex }
    }

    func saveDocument(_ document: StoredDocument) async throws {
        documentValues[document.id] = document
    }

    func deleteDocument(id: UUID) async throws {
        documentValues[id] = nil
    }

    func tags() async throws -> [WatakeDomain.Tag] {
        Array(tagValues.values)
    }

    func saveTag(_ tag: WatakeDomain.Tag) async throws {
        tagValues[tag.id] = tag
    }

    func watermarkPresets() async throws -> [WatermarkPreset] {
        []
    }

    func saveWatermarkPreset(_ preset: WatermarkPreset) async throws {}
}

private func makeFolder() -> Folder {
    Folder(id: UUID(), name: "Archive", colorHex: "#3B82F6", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
}

private func makeDocument(folder: Folder, order: Int) -> StoredDocument {
    let bytes = Data("page".utf8)
    let reference = AssetReference(
        id: UUID(), relativePath: "documents/\(UUID().uuidString.lowercased())/source/page.jpg",
        sha256Hex: "d3" + String(repeating: "0", count: 62), byteSize: bytes.count, mediaType: "image/jpeg"
    )
    return StoredDocument(
        id: UUID(), folderId: folder.id, name: "Scan", createdAt: folder.createdAt, updatedAt: folder.createdAt,
        orderIndex: order, pages: [DocumentPage(id: UUID(), index: 0, source: reference)]
    )
}

private struct TestStorageRoot: StorageRootResolving {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    func resolveRoot() throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
