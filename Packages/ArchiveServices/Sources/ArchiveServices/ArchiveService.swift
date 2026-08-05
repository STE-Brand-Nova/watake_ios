import Foundation
import WatakeDomain

public enum ArchiveError: Error, Equatable, Sendable {
    case folderUnavailable
    case documentUnavailable
    case folderTrashed
    case documentTrashed
    case tagUnavailable
    case invalidReorder
    case sameFolder
}

/// Curated tag colors from `Design.md`. UI presents these as named swatches;
/// storage persists their shared-contract hex values only.
public enum ArchiveTagPalette {
    public static let colors = [
        "#EF4444", "#F97316", "#F59E0B", "#EAB308", "#84CC16", "#22C55E",
        "#14B8A6", "#06B6D4", "#3B82F6", "#8B5CF6", "#EC4899", "#64748B"
    ]
}

/// All metadata edits replace validated value records. The repository remains
/// the storage boundary, so SwiftData/File storage adapters can be substituted
/// without leaking mutable persistence objects into feature code.
public actor ArchiveService {
    private let repository: any DocumentRepository
    private let now: @Sendable () -> Date

    public init(repository: any DocumentRepository, now: @escaping @Sendable () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    public func createFolder(name: String, colorHex: String) async throws -> Folder {
        let folder = Folder(id: UUID(), name: name, colorHex: colorHex, createdAt: now())
        try folder.validate()
        try await repository.saveFolder(folder)
        return folder
    }

    public func rename(folderId: UUID, to name: String) async throws -> Folder {
        guard let folder = try await repository.folder(id: folderId) else { throw ArchiveError.folderUnavailable }
        guard folder.deletedAt == nil else { throw ArchiveError.folderTrashed }
        let updated = Folder(id: folder.id, name: name, colorHex: folder.colorHex, createdAt: folder.createdAt)
        try updated.validate()
        try await repository.saveFolder(updated)
        return updated
    }

    public func recolor(folderId: UUID, colorHex: String) async throws -> Folder {
        guard let folder = try await repository.folder(id: folderId) else { throw ArchiveError.folderUnavailable }
        guard folder.deletedAt == nil else { throw ArchiveError.folderTrashed }
        let updated = Folder(id: folder.id, name: folder.name, colorHex: colorHex, createdAt: folder.createdAt)
        try updated.validate()
        try await repository.saveFolder(updated)
        return updated
    }

    public func rename(documentId: UUID, to name: String) async throws -> StoredDocument {
        guard let document = try await repository.document(id: documentId) else { throw ArchiveError.documentUnavailable }
        guard document.deletedAt == nil else { throw ArchiveError.documentTrashed }
        let updated = replacing(document, name: name, updatedAt: now())
        try await repository.saveDocument(updated)
        return updated
    }

    /// Moves an active document into a different active folder, appending it
    /// to the end of the destination's custom order. Preserves the document's
    /// ID, pages, tags, creation date, and asset references — only `folderId`,
    /// `orderIndex`, and `updatedAt` change.
    public func move(documentId: UUID, toFolderId: UUID) async throws -> StoredDocument {
        guard let document = try await repository.document(id: documentId) else { throw ArchiveError.documentUnavailable }
        guard document.deletedAt == nil else { throw ArchiveError.documentTrashed }
        guard document.folderId != toFolderId else { throw ArchiveError.sameFolder }
        guard let destination = try await repository.folder(id: toFolderId) else { throw ArchiveError.folderUnavailable }
        guard destination.deletedAt == nil else { throw ArchiveError.folderTrashed }
        let destinationDocuments = try await repository.documents(in: toFolderId).filter { $0.deletedAt == nil }
        let nextOrderIndex = (destinationDocuments.map(\.orderIndex).max() ?? -1) + 1
        let moved = replacing(document, folderId: toFolderId, orderIndex: nextOrderIndex, updatedAt: now())
        try await repository.moveDocument(moved)
        return moved
    }

    /// Persists only a complete, duplicate-free permutation of active folder documents.
    public func reorderDocuments(in folderId: UUID, ids: [UUID]) async throws {
        let active = try await repository.documents(in: folderId).filter { $0.deletedAt == nil }
        guard Set(active.map(\.id)) == Set(ids), active.count == ids.count else { throw ArchiveError.invalidReorder }
        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        for (index, id) in ids.enumerated() {
            guard let document = byID[id] else { throw ArchiveError.invalidReorder }
            try await repository.saveDocument(replacing(document, orderIndex: index, updatedAt: now()))
        }
    }

    public func createTag(label: String, colorHex: String) async throws -> Tag {
        let tag = Tag(id: UUID(), label: label, colorHex: colorHex)
        try tag.validate()
        try await repository.saveTag(tag)
        return tag
    }

    public func assign(tagIds: [UUID], to documentId: UUID) async throws -> StoredDocument {
        guard Set(tagIds).count == tagIds.count else { throw ArchiveError.tagUnavailable }
        let allTags = try await repository.tags()
        guard Set(tagIds).isSubset(of: Set(allTags.map(\.id))) else { throw ArchiveError.tagUnavailable }
        guard let document = try await repository.document(id: documentId) else { throw ArchiveError.documentUnavailable }
        guard document.deletedAt == nil else { throw ArchiveError.documentTrashed }
        let updated = replacing(document, tagIds: tagIds, updatedAt: now())
        try await repository.saveDocument(updated)
        return updated
    }

    public func moveToTrash(documentId: UUID) async throws {
        guard let document = try await repository.document(id: documentId) else { throw ArchiveError.documentUnavailable }
        guard document.deletedAt == nil else { throw ArchiveError.documentTrashed }
        try await repository.saveDocument(replacing(document, deletedAt: now(), updatedAt: now()))
    }

    public func restore(documentId: UUID) async throws {
        guard let document = try await repository.document(id: documentId) else { throw ArchiveError.documentUnavailable }
        guard document.deletedAt != nil else { throw ArchiveError.documentTrashed }
        guard let folder = try await repository.folder(id: document.folderId), folder.deletedAt == nil else {
            throw ArchiveError.folderUnavailable
        }
        try await repository.saveDocument(replacing(document, deletedAt: .some(nil), updatedAt: now()))
    }

    public func moveToTrash(folderId: UUID) async throws {
        guard let folder = try await repository.folder(id: folderId) else { throw ArchiveError.folderUnavailable }
        guard folder.deletedAt == nil else { throw ArchiveError.folderTrashed }
        let timestamp = now()
        // Folder tombstone hides all children without changing their own
        // tombstones. This preserves independently deleted documents and
        // avoids child writes after file storage rejects trashed folders.
        try await repository.saveFolder(Folder(
            id: folder.id, name: folder.name, colorHex: folder.colorHex, createdAt: folder.createdAt, deletedAt: timestamp
        ))
    }

    public func restore(folderId: UUID) async throws {
        guard let folder = try await repository.folder(id: folderId) else { throw ArchiveError.folderUnavailable }
        guard folder.deletedAt != nil else { throw ArchiveError.folderTrashed }
        try await repository.saveFolder(Folder(id: folder.id, name: folder.name, colorHex: folder.colorHex, createdAt: folder.createdAt))
    }

    public static func retentionDaysRemaining(deletedAt: Date, now: Date) -> Int {
        max(0, Int(ceil(deletedAt.addingTimeInterval(30 * 86400).timeIntervalSince(now) / 86400)))
    }

    private func replacing(
        _ document: StoredDocument,
        name: String? = nil,
        folderId: UUID? = nil,
        orderIndex: Int? = nil,
        tagIds: [UUID]? = nil,
        deletedAt: Date?? = nil,
        updatedAt: Date
    ) -> StoredDocument {
        StoredDocument(
            id: document.id,
            folderId: folderId ?? document.folderId,
            name: name ?? document.name,
            createdAt: document.createdAt,
            updatedAt: updatedAt,
            orderIndex: orderIndex ?? document.orderIndex,
            pages: document.pages,
            deletedAt: deletedAt ?? document.deletedAt,
            tagIds: tagIds ?? document.tagIds,
            watermarkPresetId: document.watermarkPresetId
        )
    }
}
