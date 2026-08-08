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

    @Test func assignRejectsDuplicateOrUnknownIDs() async throws {
        let folder = makeFolder()
        let document = makeDocument(folder: folder, order: 0)
        let red = WatakeDomain.Tag(id: UUID(), label: "Work", colorHex: ArchiveTagPalette.colors[0])
        let repository = MemoryRepository(folder: folder, documents: [document], tags: [red])
        let service = ArchiveService(repository: repository)

        await #expect(throws: ArchiveError.tagUnavailable) {
            try await service.assign(tagIds: [red.id, red.id], to: document.id)
        }
        await #expect(throws: ArchiveError.tagUnavailable) {
            try await service.assign(tagIds: [UUID()], to: document.id)
        }
    }

    @Test func sharedTagSurvivesUnassignmentFromOneDocument() async throws {
        let folder = makeFolder()
        let first = makeDocument(folder: folder, order: 0)
        let second = makeDocument(folder: folder, order: 1)
        let shared = WatakeDomain.Tag(id: UUID(), label: "Shared", colorHex: ArchiveTagPalette.colors[2])
        let repository = MemoryRepository(folder: folder, documents: [first, second], tags: [shared])
        let service = ArchiveService(repository: repository)

        _ = try await service.assign(tagIds: [shared.id], to: first.id)
        _ = try await service.assign(tagIds: [shared.id], to: second.id)
        let firstAfterUnassign = try await service.assign(tagIds: [], to: first.id)

        #expect(firstAfterUnassign.tagIds.isEmpty)
        #expect(try await repository.document(id: second.id)?.tagIds == [shared.id])
        #expect(try await repository.tags().map(\.id).contains(shared.id) == true)
    }

    @Test func palettePreservesOrderAndValues() {
        #expect(ArchiveTagPalette.colors == [
            "#EF4444", "#F97316", "#F59E0B", "#EAB308", "#84CC16", "#22C55E",
            "#14B8A6", "#06B6D4", "#3B82F6", "#8B5CF6", "#EC4899", "#64748B"
        ])
    }

    @Test func createTagTrimsCanonicalLabel() async throws {
        let repository = MemoryRepository(folder: makeFolder(), documents: [])
        let service = ArchiveService(repository: repository)

        let tag = try await service.createTag(label: "  Receipts  ", colorHex: ArchiveTagPalette.colors[0])
        #expect(tag.label == "Receipts")
    }

    @Test func createTagRejectsEmptyLabel() async throws {
        let repository = MemoryRepository(folder: makeFolder(), documents: [])
        let service = ArchiveService(repository: repository)

        await #expect(throws: DomainValidationError.self) {
            try await service.createTag(label: "   ", colorHex: ArchiveTagPalette.colors[0])
        }
    }

    @Test func createTagRejectsOverLongLabel() async throws {
        let repository = MemoryRepository(folder: makeFolder(), documents: [])
        let service = ArchiveService(repository: repository)
        let tooLong = String(repeating: "a", count: 51)

        await #expect(throws: DomainValidationError.self) {
            try await service.createTag(label: tooLong, colorHex: ArchiveTagPalette.colors[0])
        }
    }

    @Test func createTagRejectsDuplicateLabelIgnoringCase() async throws {
        let existing = WatakeDomain.Tag(id: UUID(), label: "Receipts", colorHex: ArchiveTagPalette.colors[0])
        let repository = MemoryRepository(folder: makeFolder(), documents: [], tags: [existing])
        let service = ArchiveService(repository: repository)

        await #expect(throws: ArchiveError.duplicateTagLabel) {
            try await service.createTag(label: "  receipts  ", colorHex: ArchiveTagPalette.colors[1])
        }
    }

    @Test func createTagRejectsNonPaletteColor() async throws {
        let repository = MemoryRepository(folder: makeFolder(), documents: [])
        let service = ArchiveService(repository: repository)

        await #expect(throws: ArchiveError.invalidTagColor) {
            try await service.createTag(label: "Receipts", colorHex: "#123456")
        }
    }

    @Test func updateTagPreservesIDAndChangesValue() async throws {
        let original = WatakeDomain.Tag(id: UUID(), label: "Old", colorHex: ArchiveTagPalette.colors[0])
        let repository = MemoryRepository(folder: makeFolder(), documents: [], tags: [original])
        let service = ArchiveService(repository: repository)

        let updated = try await service.updateTag(id: original.id, label: "  New  ", colorHex: ArchiveTagPalette.colors[3])
        #expect(updated.id == original.id)
        #expect(updated.label == "New")
        #expect(updated.colorHex == ArchiveTagPalette.colors[3])
        #expect(try await repository.tags().first { $0.id == original.id }?.label == "New")
    }

    @Test func updateTagAllowsKeepingItsOwnLabel() async throws {
        let original = WatakeDomain.Tag(id: UUID(), label: "Receipts", colorHex: ArchiveTagPalette.colors[0])
        let repository = MemoryRepository(folder: makeFolder(), documents: [], tags: [original])
        let service = ArchiveService(repository: repository)

        let updated = try await service.updateTag(id: original.id, label: "Receipts", colorHex: ArchiveTagPalette.colors[1])
        #expect(updated.colorHex == ArchiveTagPalette.colors[1])
    }

    @Test func updateTagRejectsDuplicateAgainstAnotherTag() async throws {
        let first = WatakeDomain.Tag(id: UUID(), label: "Receipts", colorHex: ArchiveTagPalette.colors[0])
        let second = WatakeDomain.Tag(id: UUID(), label: "Invoices", colorHex: ArchiveTagPalette.colors[1])
        let repository = MemoryRepository(folder: makeFolder(), documents: [], tags: [first, second])
        let service = ArchiveService(repository: repository)

        await #expect(throws: ArchiveError.duplicateTagLabel) {
            try await service.updateTag(id: second.id, label: "receipts", colorHex: ArchiveTagPalette.colors[1])
        }
    }

    @Test func updateTagRejectsNonPaletteColor() async throws {
        let tag = WatakeDomain.Tag(id: UUID(), label: "Receipts", colorHex: ArchiveTagPalette.colors[0])
        let repository = MemoryRepository(folder: makeFolder(), documents: [], tags: [tag])
        let service = ArchiveService(repository: repository)

        await #expect(throws: ArchiveError.invalidTagColor) {
            try await service.updateTag(id: tag.id, label: "Receipts", colorHex: "#123456")
        }
    }

    @Test func updateTagRejectsUnknownID() async throws {
        let repository = MemoryRepository(folder: makeFolder(), documents: [])
        let service = ArchiveService(repository: repository)

        await #expect(throws: ArchiveError.tagUnavailable) {
            try await service.updateTag(id: UUID(), label: "Receipts", colorHex: ArchiveTagPalette.colors[0])
        }
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

    @Test func moveDocumentPreservesIdentityAndAppendsToDestinationEnd() async throws {
        let source = makeFolder(name: "Source")
        let destination = makeFolder(name: "Destination")
        let moving = makeDocument(folder: source, order: 0)
        let existingInDestination = makeDocument(folder: destination, order: 0)
        let repository = MemoryRepository(
            folder: source, additionalFolders: [destination], documents: [moving, existingInDestination]
        )
        let timestamp = Date(timeIntervalSince1970: 1_700_002_000)
        let service = ArchiveService(repository: repository, now: { timestamp })

        let moved = try await service.move(documentId: moving.id, toFolderId: destination.id)

        #expect(moved.id == moving.id)
        #expect(moved.folderId == destination.id)
        #expect(moved.orderIndex == 1)
        #expect(moved.pages == moving.pages)
        #expect(moved.tagIds == moving.tagIds)
        #expect(moved.createdAt == moving.createdAt)
        #expect(moved.updatedAt == timestamp)
        let persisted = try #require(try await repository.document(id: moving.id))
        #expect(persisted.folderId == destination.id)
    }

    @Test func moveDocumentRejectsSameFolder() async throws {
        let folder = makeFolder()
        let document = makeDocument(folder: folder, order: 0)
        let repository = MemoryRepository(folder: folder, documents: [document])
        let service = ArchiveService(repository: repository)

        await #expect(throws: ArchiveError.sameFolder) {
            try await service.move(documentId: document.id, toFolderId: folder.id)
        }
    }

    @Test func moveDocumentRejectsUnknownDestination() async throws {
        let folder = makeFolder()
        let document = makeDocument(folder: folder, order: 0)
        let repository = MemoryRepository(folder: folder, documents: [document])
        let service = ArchiveService(repository: repository)

        await #expect(throws: ArchiveError.folderUnavailable) {
            try await service.move(documentId: document.id, toFolderId: UUID())
        }
    }

    @Test func moveDocumentRejectsTrashedDestination() async throws {
        let folder = makeFolder()
        let trashedDestination = makeFolder(name: "Trashed", deletedAt: Date(timeIntervalSince1970: 1_700_001_500))
        let document = makeDocument(folder: folder, order: 0)
        let repository = MemoryRepository(folder: folder, additionalFolders: [trashedDestination], documents: [document])
        let service = ArchiveService(repository: repository)

        await #expect(throws: ArchiveError.folderTrashed) {
            try await service.move(documentId: document.id, toFolderId: trashedDestination.id)
        }
    }

    @Test func movedDocumentTrashAndRestoreStayCorrect() async throws {
        let source = makeFolder(name: "Source")
        let destination = makeFolder(name: "Destination")
        let document = makeDocument(folder: source, order: 0)
        let repository = MemoryRepository(folder: source, additionalFolders: [destination], documents: [document])
        let service = ArchiveService(repository: repository)

        _ = try await service.move(documentId: document.id, toFolderId: destination.id)
        try await service.moveToTrash(documentId: document.id)
        let trashed = try #require(try await repository.document(id: document.id))
        #expect(trashed.folderId == destination.id)
        #expect(trashed.deletedAt != nil)

        try await service.restore(documentId: document.id)
        let restored = try #require(try await repository.document(id: document.id))
        #expect(restored.folderId == destination.id)
        #expect(restored.deletedAt == nil)
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

    @Test func tagCreateAndAssignSurviveFileStorageReload() async throws {
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

        let tag = try await archive.createTag(label: "Receipts", colorHex: ArchiveTagPalette.colors[0])
        _ = try await archive.assign(tagIds: [tag.id], to: document.id)

        let reloadedStorage = WatakeFileStorage(
            rootResolver: root,
            protectionApplier: UntilFirstUnlockFileProtection(),
            encryptionKeyStore: KeychainEncryptionKeyStore(service: serviceName)
        )
        #expect(try await reloadedStorage.tags().map(\.id) == [tag.id])
        #expect(try await reloadedStorage.document(id: document.id)?.tagIds == [tag.id])
    }
}

private actor MemoryRepository: DocumentRepository {
    private var folderValues: [UUID: Folder]
    private var documentValues: [UUID: StoredDocument]
    private var tagValues: [UUID: WatakeDomain.Tag]

    init(folder: Folder, additionalFolders: [Folder] = [], documents: [StoredDocument], tags: [WatakeDomain.Tag] = []) {
        var folders = [folder.id: folder]
        for extra in additionalFolders {
            folders[extra.id] = extra
        }
        folderValues = folders
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

    func moveDocument(_ document: StoredDocument) async throws {
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

private func makeFolder(name: String = "Archive", deletedAt: Date? = nil) -> Folder {
    Folder(id: UUID(), name: name, colorHex: "#3B82F6", createdAt: Date(timeIntervalSince1970: 1_700_000_000), deletedAt: deletedAt)
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
