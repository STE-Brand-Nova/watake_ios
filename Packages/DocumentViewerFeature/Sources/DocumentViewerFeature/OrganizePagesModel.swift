import Foundation
import Observation
import WatakeDomain

public enum OrganizePagesError: Error, Equatable, Sendable {
    case documentChanged
    case unavailable
}

/// In-memory page-order draft. Persistence occurs once, only when `save()` is
/// called. Page IDs and page-scoped data remain stable while current indexes
/// are rewritten contiguously.
@MainActor
@Observable
final class OrganizePagesModel {
    private(set) var pages: [DocumentPage]
    private(set) var isSaving = false
    private(set) var error: OrganizePagesError?

    private var baselinePageIDs: [UUID]
    private let documentID: UUID
    private let loadDocument: @Sendable (UUID) async throws -> StoredDocument?
    private let saveDocument: @Sendable (StoredDocument) async throws -> Void
    private let loadThumbnail: @Sendable (DocumentPage) async throws -> Data
    private let onPersisted: @MainActor @Sendable (StoredDocument) -> Void

    init(
        document: StoredDocument,
        loadDocument: @escaping @Sendable (UUID) async throws -> StoredDocument?,
        saveDocument: @escaping @Sendable (StoredDocument) async throws -> Void,
        loadThumbnail: @escaping @Sendable (DocumentPage) async throws -> Data,
        onPersisted: @escaping @MainActor @Sendable (StoredDocument) -> Void
    ) {
        let orderedPages = document.pages.sorted { $0.index < $1.index }
        pages = orderedPages
        baselinePageIDs = orderedPages.map(\.id)
        documentID = document.id
        self.loadDocument = loadDocument
        self.saveDocument = saveDocument
        self.loadThumbnail = loadThumbnail
        self.onPersisted = onPersisted
    }

    var hasChanges: Bool {
        pages.map(\.id) != baselinePageIDs
    }

    var canRestoreOriginalOrder: Bool {
        pages.map(\.id) != pages.sorted(by: originalOrder).map(\.id)
    }

    func loadThumbnailData(for page: DocumentPage) async throws -> Data {
        try await loadThumbnail(page)
    }

    func move(pageID: UUID, before targetID: UUID) {
        guard pageID != targetID,
              let source = pages.firstIndex(where: { $0.id == pageID }),
              let target = pages.firstIndex(where: { $0.id == targetID }) else { return }
        let page = pages.remove(at: source)
        let insertionIndex = source < target ? target - 1 : target
        pages.insert(page, at: insertionIndex)
        reindexDraft()
    }

    func moveEarlier(pageID: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == pageID }), index > 0 else { return }
        pages.swapAt(index, index - 1)
        reindexDraft()
    }

    func moveLater(pageID: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == pageID }), index < pages.count - 1 else { return }
        pages.swapAt(index, index + 1)
        reindexDraft()
    }

    func restoreOriginalOrder() {
        pages.sort(by: originalOrder)
        reindexDraft()
    }

    func clearError() {
        error = nil
    }

    @discardableResult
    func save() async -> Bool {
        guard !isSaving else { return false }
        guard hasChanges else { return true }
        isSaving = true
        defer { isSaving = false }

        do {
            guard let latest = try await loadDocument(documentID) else {
                throw OrganizePagesError.unavailable
            }
            let updated = try updatedDocument(from: latest)
            try updated.validate()
            try await saveDocument(updated)
            pages = updated.pages
            baselinePageIDs = updated.pages.map(\.id)
            onPersisted(updated)
            return true
        } catch let organizationError as OrganizePagesError {
            error = organizationError
            return false
        } catch {
            self.error = .unavailable
            return false
        }
    }

    private func updatedDocument(from latest: StoredDocument) throws -> StoredDocument {
        let latestByID = Dictionary(uniqueKeysWithValues: latest.pages.map { ($0.id, $0) })
        guard Set(latestByID.keys) == Set(pages.map(\.id)) else {
            throw OrganizePagesError.documentChanged
        }
        let reordered = try pages.enumerated().map { index, draftPage in
            guard let currentPage = latestByID[draftPage.id] else {
                throw OrganizePagesError.documentChanged
            }
            return reindexed(currentPage, to: index)
        }
        return StoredDocument(
            id: latest.id,
            folderId: latest.folderId,
            name: latest.name,
            createdAt: latest.createdAt,
            updatedAt: Date(),
            orderIndex: latest.orderIndex,
            pages: reordered,
            deletedAt: latest.deletedAt,
            tagIds: latest.tagIds,
            watermarkPresetId: latest.watermarkPresetId
        )
    }

    private func reindexDraft() {
        pages = pages.enumerated().map { index, page in
            reindexed(page, to: index)
        }
    }

    private func reindexed(_ page: DocumentPage, to index: Int) -> DocumentPage {
        DocumentPage(
            id: page.id,
            index: index,
            originalIndex: page.originalIndex,
            source: page.source,
            rectified: page.rectified,
            ocrText: page.ocrText,
            ocrBlocks: page.ocrBlocks,
            annotations: page.annotations
        )
    }

    private func originalOrder(_ lhs: DocumentPage, _ rhs: DocumentPage) -> Bool {
        lhs.originalIndex != rhs.originalIndex
            ? lhs.originalIndex < rhs.originalIndex
            : lhs.id.uuidString < rhs.id.uuidString
    }
}
