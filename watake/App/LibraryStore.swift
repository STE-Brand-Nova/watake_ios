import ArchiveServices
import CaptureServices
import DocumentProcessing
import DocumentSearchFeature
import DocumentViewerFeature
import Foundation
import Observation
import WatakeDomain
import WatakeStorage

/// A folder's chosen document presentation. Held in-session only on
/// `LibraryStore` (not persisted): the app has no existing preferences
/// mechanism, and introducing one (e.g. SwiftData) just for this would be
/// disproportionate. Stable across navigating within the folder for the
/// current app session, reset on relaunch.
enum DocumentLayout: String, CaseIterable {
    case list
    case grid
}

/// Session-only offer for restoring the latest item sent to Trash. The item is
/// already durably soft-deleted; this only controls temporary Library UI.
enum TrashItemID: Equatable, Sendable {
    case document(UUID)
    case folder(UUID)
}

struct PendingTrashUndo: Equatable, Sendable {
    let id: UUID
    let item: TrashItemID
}

/// Degraded thumbnail path used only if `ThumbnailCache` construction fails
/// (e.g. Caches directory unavailable). Reads the full-resolution asset
/// uncached rather than making the rail non-functional; `DocumentPageThumbnailProvider`
/// is used whenever the cache is available.
private struct RawAssetThumbnailFallback: DocumentPageThumbnailLoading {
    let assetStore: any DocumentAssetStore

    func thumbnail(for page: DocumentPage) async throws -> Data {
        if let rectified = page.rectified, let data = try? await assetStore.readAsset(rectified) {
            return data
        }
        return try await assetStore.readAsset(page.source)
    }
}

@MainActor
@Observable
final class LibraryStore {
    private let storage: WatakeFileStorage
    private let archive: ArchiveService
    private let importer: ImportedDocumentService
    private let thumbnailCache: ThumbnailCache?
    private let ocrRecognizer: VisionOCRRecognizer
    private let undoDuration: Duration
    private let undoSleeper: @Sendable (Duration) async throws -> Void
    let searchModel: DocumentSearchModel

    private(set) var folders: [Folder] = []
    private(set) var documentsByFolder: [UUID: [StoredDocument]] = [:]
    private(set) var tags: [Tag] = []
    var errorMessage: String?
    var isLoading = false
    private(set) var pendingTrashUndo: PendingTrashUndo?
    private var undoExpiryTask: Task<Void, Never>?

    /// Routing state for the document viewer, kept here (above the compact/
    /// regular/expanded shell split) so opening a document and its selected
    /// page survive width-class changes. Routes by `DocumentID`, never a
    /// `StoredDocument` instance or file URL.
    private(set) var selectedDocumentID: UUID?
    private(set) var selectedFolderID: UUID?
    private var viewerModels: [UUID: DocumentViewerModel] = [:]

    private var layoutByFolder: [UUID: DocumentLayout] = [:]

    /// In-session, single-tag filter for the active folder's document
    /// browser. Not persisted and kept above the compact/regular/expanded
    /// layout branch so a width-class change never discards it.
    private(set) var selectedTagFilterID: UUID?

    convenience init() {
        self.init(
            storageSubdirectory: "Watake",
            keychainService: "com.watake.assets"
        )
    }

    /// Test-only seam: a distinct `storageSubdirectory`/`keychainService`
    /// isolates a `LibraryStore` instance's Application Support directory and
    /// keychain items from the real app archive and from other test runs.
    init(
        storageSubdirectory: String,
        keychainService: String,
        undoDuration: Duration = .seconds(5),
        undoSleeper: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        let storage = WatakeFileStorage(
            rootResolver: ApplicationSupportRootResolver(subdirectory: storageSubdirectory),
            protectionApplier: UntilFirstUnlockFileProtection(),
            encryptionKeyStore: KeychainEncryptionKeyStore(service: keychainService)
        )
        self.storage = storage
        archive = ArchiveService(repository: storage)
        importer = ImportedDocumentService(repository: storage, assetStore: storage, serialiser: FolderScanOperationSerialiser())
        thumbnailCache = try? ThumbnailCache()
        ocrRecognizer = VisionOCRRecognizer()
        self.undoDuration = undoDuration
        self.undoSleeper = undoSleeper
        searchModel = DocumentSearchModel(searcher: LocalDocumentSearchService(repository: storage))
    }

    var activeFolders: [Folder] {
        folders.filter { $0.deletedAt == nil }
    }

    var trashedFolders: [Folder] {
        folders.filter { $0.deletedAt != nil }
    }

    func documents(in folder: Folder) -> [StoredDocument] {
        guard self.folder(for: folder.id)?.deletedAt == nil else { return [] }
        return (documentsByFolder[folder.id] ?? []).filter { $0.deletedAt == nil }.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// `documents(in:)` filtered by `selectedTagFilterID`, if any. Never
    /// changes folder counts, ordering, or persisted preferences — folder
    /// cards must keep calling the unfiltered `documents(in:)`.
    func filteredDocuments(in folder: Folder) -> [StoredDocument] {
        let ordered = documents(in: folder)
        guard let selectedTagFilterID else { return ordered }
        return ordered.filter { $0.tagIds.contains(selectedTagFilterID) }
    }

    func setTagFilter(_ tag: Tag?) {
        selectedTagFilterID = tag?.id
    }

    var trashedDocuments: [StoredDocument] {
        documentsByFolder.values.flatMap(\.self).filter { $0.deletedAt != nil }
    }

    var watermarkPresetStore: any WatermarkPresetStore {
        storage
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let folders = try await storage.folders()
            var pages: [UUID: [StoredDocument]] = [:]
            for folder in folders {
                pages[folder.id] = try await storage.documents(in: folder.id)
            }
            self.folders = folders
            documentsByFolder = pages
            tags = try await storage.tags()
        } catch {
            errorMessage = "Archive could not load. Try again."
        }
    }

    func createFolder(name: String, colorHex: String = ArchiveTagPalette.colors[8]) async -> Folder? {
        do {
            let folder = try await archive.createFolder(name: name, colorHex: colorHex)
            await load()
            return folder
        } catch {
            errorMessage = "Could not create folder. Try again."
            return nil
        }
    }

    func renameFolder(_ folder: Folder, name: String) async {
        await run { _ = try await archive.rename(folderId: folder.id, to: name) }
    }

    func recolorFolder(_ folder: Folder, colorHex: String) async {
        await run {
            _ = try await archive.recolor(folderId: folder.id, colorHex: colorHex)
        }
    }

    func renameDocument(_ document: StoredDocument, name: String) async {
        await run {
            _ = try await archive.rename(documentId: document.id, to: name)
        }
    }

    func reorder(folder: Folder, documents: [StoredDocument]) async {
        await run { try await archive.reorderDocuments(in: folder.id, ids: documents.map(\.id)) }
    }

    /// Moves `document` into `destination`. Returns whether the move
    /// succeeded; a recoverable, user-facing message is set on
    /// `errorMessage` for the same/trashed/unavailable destination cases
    /// instead of the generic fallback `run(_:)` message.
    func moveDocument(_ document: StoredDocument, to destination: Folder) async -> Bool {
        do {
            _ = try await archive.move(documentId: document.id, toFolderId: destination.id)
            await load()
            return true
        } catch let error as ArchiveError {
            errorMessage = moveErrorMessage(error)
            return false
        } catch {
            errorMessage = "Could not move document. Try again."
            return false
        }
    }

    private func moveErrorMessage(_ error: ArchiveError) -> String {
        switch error {
        case .sameFolder:
            "This document is already in that folder."
        case .folderTrashed:
            "Can't move a document into a folder that's in Trash."
        case .folderUnavailable:
            "That folder is no longer available."
        case .documentTrashed:
            "Can't move a document that's in Trash."
        default:
            "Could not move document. Try again."
        }
    }

    /// Returns the created tag on success, or `nil` with `errorMessage` set
    /// (duplicate label / non-palette color / persistence failure) so callers
    /// can preserve the user's input instead of clearing it.
    func createTag(label: String, colorHex: String) async -> Tag? {
        do {
            let tag = try await archive.createTag(label: label, colorHex: colorHex)
            await load()
            return tag
        } catch let error as ArchiveError {
            errorMessage = tagErrorMessage(error)
            return nil
        } catch {
            errorMessage = "Could not save changes. Your original pages are unchanged."
            return nil
        }
    }

    /// Returns the updated tag on success, or `nil` with `errorMessage` set.
    func editTag(_ tag: Tag, label: String, colorHex: String) async -> Tag? {
        do {
            let updated = try await archive.updateTag(id: tag.id, label: label, colorHex: colorHex)
            await load()
            return updated
        } catch let error as ArchiveError {
            errorMessage = tagErrorMessage(error)
            return nil
        } catch {
            errorMessage = "Could not save changes. Your original pages are unchanged."
            return nil
        }
    }

    private func tagErrorMessage(_ error: ArchiveError) -> String {
        switch error {
        case .duplicateTagLabel:
            "A tag with that name already exists."
        case .invalidTagColor:
            "Choose one of the available tag colors."
        default:
            "Could not save changes. Your original pages are unchanged."
        }
    }

    /// Returns whether the assignment succeeded so callers (e.g. the tag
    /// assignment sheet) can keep the sheet open and show the error on
    /// failure instead of dismissing as if it saved.
    func assign(tagIds: [UUID], document: StoredDocument) async -> Bool {
        do {
            _ = try await archive.assign(tagIds: tagIds, to: document.id)
            await load()
            return true
        } catch {
            errorMessage = "Could not save changes. Your original pages are unchanged."
            return false
        }
    }

    func save(pages: [ImportedPage], grouping: GalleryGrouping, folder: Folder, name: String) async -> Bool {
        do {
            _ = try await importer.save(pages: pages, grouping: grouping, into: folder.id, named: name)
            await load()
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = "Could not save capture. Review pages remain available to retry."
            return false
        }
    }

    func folder(for id: UUID) -> Folder? {
        folders.first { $0.id == id }
    }

    func layout(for folder: Folder) -> DocumentLayout {
        layoutByFolder[folder.id] ?? .list
    }

    func setLayout(_ layout: DocumentLayout, for folder: Folder) {
        layoutByFolder[folder.id] = layout
    }

    func openDocument(_ document: StoredDocument) {
        selectedFolderID = document.folderId
        selectedDocumentID = document.id
    }

    func openFolder(id: UUID) {
        selectedDocumentID = nil
        selectedFolderID = id
    }

    func closeFolder() {
        closeDocument()
        selectedFolderID = nil
    }

    func openSearchResult(_ result: ArchiveSearchResult) {
        switch result {
        case .folder(let folder):
            openFolder(id: folder.id)
        case .document(let document):
            selectedFolderID = document.folderID
            selectedDocumentID = document.id
        }
    }

    /// Keeps the search field and rendered search state in the same feature
    /// model when the app shell switches away from Search.
    func resetSearch() {
        searchModel.reset()
    }

    func closeDocument() {
        if let id = selectedDocumentID {
            viewerModels[id]?.cancel()
            viewerModels[id] = nil
        }
        selectedDocumentID = nil
    }

    /// Returns the same model instance for a given `DocumentID` across
    /// repeated calls (e.g. across compact/regular re-layouts) so an
    /// in-progress or completed load is never discarded by a width change.
    func documentViewerModel(for documentID: UUID) -> DocumentViewerModel {
        if let existing = viewerModels[documentID] {
            return existing
        }
        let thumbnailLoader: any DocumentPageThumbnailLoading = thumbnailCache.map {
            DocumentPageThumbnailProvider(assetStore: storage, cache: $0)
        } ?? RawAssetThumbnailFallback(assetStore: storage)
        let model = DocumentViewerModel(
            documentID: documentID,
            loader: storage,
            thumbnailLoader: thumbnailLoader,
            ocrRecognizer: ocrRecognizer,
            ocrStore: storage,
            onOCRPersisted: { [weak self] document in
                self?.replaceCachedDocument(document)
            }
        )
        viewerModels[documentID] = model
        return model
    }

    func thumbnailData(for document: StoredDocument) async -> Data? {
        guard let cache = thumbnailCache, let page = document.pages.first else { return nil }
        let asset = page.rectified ?? page.source
        do {
            let sourceData = try await storage.readAsset(asset)
            return try await cache.thumbnail(for: asset, data: sourceData)
        } catch {
            return nil
        }
    }

    private func replaceCachedDocument(_ document: StoredDocument) {
        guard var documents = documentsByFolder[document.folderId] else { return }
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[index] = document
        documentsByFolder[document.folderId] = documents
    }

    private func run(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            await load()
        } catch is CancellationError {
            // User cancellation is intentionally silent.
        } catch {
            errorMessage = "Could not save changes. Your original pages are unchanged."
        }
    }
}

// MARK: - Trash

extension LibraryStore {
    /// Returns true only after the durable soft deletion succeeds. A failed
    /// operation does not replace an existing Undo offer.
    func trashDocument(_ document: StoredDocument) async -> Bool {
        await moveToTrash(.document(document.id))
    }

    /// Returns true only when the original active folder accepts restoration.
    func restoreDocument(_ document: StoredDocument) async -> Bool {
        await restoreManually(.document(document.id))
    }

    /// Returns true only after the folder tombstone is durable.
    func trashFolder(_ folder: Folder) async -> Bool {
        await moveToTrash(.folder(folder.id))
    }

    func restoreFolder(_ folder: Folder) async -> Bool {
        await restoreManually(.folder(folder.id))
    }

    /// Restores the current offer by immutable ID. An unsuccessful attempt
    /// leaves the offer visible until it expires so no success is implied.
    func undoTrash() async -> Bool {
        guard let pendingTrashUndo else { return false }
        let undoID = pendingTrashUndo.id
        let restored = await restore(pendingTrashUndo.item)
        if restored {
            clearUndoOffer(matching: undoID)
        }
        return restored
    }

    private func moveToTrash(_ item: TrashItemID) async -> Bool {
        do {
            switch item {
            case .document(let id):
                try await archive.moveToTrash(documentId: id)
            case .folder(let id):
                try await archive.moveToTrash(folderId: id)
            }
            await load()
            offerUndo(for: item)
            return true
        } catch {
            errorMessage = "Could not move item to Trash. Try again."
            return false
        }
    }

    /// A successful manual restore invalidates only an offer for the same
    /// item that existed when restoration began. A newer offer remains valid.
    private func restoreManually(_ item: TrashItemID) async -> Bool {
        let matchingOfferID = pendingTrashUndo?.item == item ? pendingTrashUndo?.id : nil
        let restored = await restore(item)
        if restored, let matchingOfferID {
            clearUndoOffer(matching: matchingOfferID)
        }
        return restored
    }

    private func restore(_ item: TrashItemID) async -> Bool {
        do {
            switch item {
            case .document(let id):
                try await archive.restore(documentId: id)
            case .folder(let id):
                try await archive.restore(folderId: id)
            }
            await load()
            return true
        } catch let error as ArchiveError {
            errorMessage = restoreErrorMessage(error)
            return false
        } catch {
            errorMessage = "Could not restore item. Try again."
            return false
        }
    }

    private func restoreErrorMessage(_ error: ArchiveError) -> String {
        switch error {
        case .folderUnavailable, .folderTrashed:
            "This item can be restored after its original folder is available."
        default:
            "Could not restore item. Try again."
        }
    }

    private func offerUndo(for item: TrashItemID) {
        undoExpiryTask?.cancel()
        let offer = PendingTrashUndo(id: UUID(), item: item)
        pendingTrashUndo = offer
        let duration = undoDuration
        let sleeper = undoSleeper
        undoExpiryTask = Task { [weak self] in
            do {
                try await sleeper(duration)
                guard !Task.isCancelled else { return }
                self?.clearUndoOffer(matching: offer.id)
            } catch is CancellationError {
                // Replaced or dismissed offers must not affect newer state.
            } catch {
                // Expiry is best-effort presentation state; archive data is safe.
            }
        }
    }

    private func clearUndoOffer(matching id: UUID) {
        guard pendingTrashUndo?.id == id else { return }
        undoExpiryTask?.cancel()
        undoExpiryTask = nil
        pendingTrashUndo = nil
    }
}
