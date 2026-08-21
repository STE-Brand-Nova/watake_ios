import ArchiveServices
import CaptureServices
import DocumentProcessing
import DocumentSearchFeature
import DocumentViewerFeature
import ExportFeature
import Foundation
import Observation
import WatakeDomain
import WatakeStorage

/// A folder's chosen document presentation. Held in-session only on
/// `LibraryStore` (not persisted): the app has no existing preferences
/// mechanism, and introducing one (e.g. SwiftData) just for this would be
/// disproportionate. Stable across navigating within the folder for the
/// current app session, reset on relaunch.
@MainActor
@Observable
final class LibraryStore {
    private let storage: WatakeFileStorage
    private let archive: ArchiveService
    private let importer: ImportedDocumentService
    private let thumbnailCache: ThumbnailCache?
    private let ocrRecognizer: VisionOCRRecognizer
    private let watermarkIssuanceService: WatermarkIssuanceService
    private let undoDuration: Duration
    private let undoSleeper: @Sendable (Duration) async throws -> Void
    let searchModel: DocumentSearchModel

    private(set) var folders: [Folder] = []
    private(set) var documentsByFolder: [UUID: [StoredDocument]] = [:]
    private(set) var tags: [Tag] = []
    private(set) var watermarkRecipients: [WatermarkRecipient] = []
    private(set) var watermarkIssuances: [WatermarkIssuance] = []
    var errorMessage: String?
    var isLoading = false
    private var isPurging = false
    private(set) var pendingTrashUndo: PendingTrashUndo?
    private var undoExpiryTask: Task<Void, Never>?
    private var temporaryExportDirectory: URL?

    /// Routing state for the document viewer, kept here (above the compact/
    /// regular/expanded shell split) so opening a document and its selected
    /// page survive width-class changes. Routes by `DocumentID`, never a
    /// `StoredDocument` instance or file URL.
    private(set) var selectedDocumentID: UUID?
    private(set) var selectedFolderID: UUID?
    private(set) var mostRecentlyUsedFolder: UUID?
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
        watermarkIssuanceService = WatermarkIssuanceService(repository: storage, assetStore: storage)
        self.undoDuration = undoDuration
        self.undoSleeper = undoSleeper
        searchModel = DocumentSearchModel(searcher: LocalDocumentSearchService(repository: storage))
    }
}

extension LibraryStore {
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

    var activeDocuments: [StoredDocument] {
        documentsByFolder.values.flatMap(\.self)
            .filter { document in
                document.deletedAt == nil && folder(for: document.folderId)?.deletedAt == nil
            }
    }

    var activeWatermarkRenditions: [WatermarkRendition] {
        watermarkIssuances.flatMap(\.renditions).filter { $0.deletedAt == nil }
    }

    var trashedWatermarkRenditions: [WatermarkRendition] {
        watermarkIssuances.flatMap(\.renditions).filter { $0.deletedAt != nil }
    }

    func copyCount(for documentID: UUID) -> Int {
        activeWatermarkRenditions.count { $0.documentId == documentID }
    }

    func copyCount(in folder: Folder) -> Int {
        let ids = Set(documents(in: folder).map(\.id))
        return activeWatermarkRenditions.count { ids.contains($0.documentId) }
    }

    func relatedCopyCount(for documentID: UUID) -> Int {
        watermarkIssuances.flatMap(\.renditions).count { $0.documentId == documentID }
    }

    func relatedCopyCount(in folder: Folder) -> Int {
        let ids = Set((documentsByFolder[folder.id] ?? []).map(\.id))
        return watermarkIssuances.flatMap(\.renditions).count { ids.contains($0.documentId) }
    }

    func issuance(containing renditionID: UUID) -> WatermarkIssuance? {
        watermarkIssuances.first { $0.renditions.contains(where: { $0.id == renditionID }) }
    }

    var watermarkPresetStore: any WatermarkPresetStore {
        storage
    }

    var watermarkAssetStore: any DocumentAssetStore {
        storage
    }

    func documents(forIDs ids: Set<UUID>) -> [StoredDocument] {
        documentsByFolder.values
            .flatMap(\.self)
            .filter { ids.contains($0.id) && $0.deletedAt == nil }
    }

    func documentIncludingTrash(id: UUID) -> StoredDocument? {
        documentsByFolder.values.flatMap(\.self).first { $0.id == id }
    }

    func makeExportModel(for documentIDs: Set<UUID>) -> ExportFeatureModel {
        let loader = LibraryExportDocumentLoader { [weak self] ids in
            guard let self else { return [] }
            return await MainActor.run {
                self.documents(forIDs: ids)
            }
        }
        let pdfRenderer = BulkPDFRenderer(assetStore: storage)
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: pdfRenderer
        )
        model.prepareDraft(documentIDs: documentIDs)
        return model
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
            watermarkRecipients = try await storage.watermarkRecipients()
            watermarkIssuances = try await storage.watermarkIssuances()
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
        mostRecentlyUsedFolder = document.folderId
    }

    func openFolder(id: UUID) {
        selectedDocumentID = nil
        selectedFolderID = id
        mostRecentlyUsedFolder = id
    }

    func markFolderUsed(_ id: UUID) {
        mostRecentlyUsedFolder = id
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

    func watermarkPreviewData(for document: StoredDocument) async -> Data? {
        guard let page = document.pages.min(by: { $0.index < $1.index }) else { return nil }
        return try? await storage.readAsset(page.rectified ?? page.source)
    }

    func watermarkRenditionPreviewData(
        _ rendition: WatermarkRendition,
        maxPixelSize: Int = 192
    ) async -> Data? {
        guard let page = rendition.pages.min(by: { $0.index < $1.index }) else { return nil }
        do {
            let data = try await storage.readAsset(page.watermarked)
            guard let thumbnailCache else { return data }
            return try await thumbnailCache.thumbnail(
                for: page.watermarked,
                data: data,
                maxPixelSize: maxPixelSize
            )
        } catch {
            return nil
        }
    }

    func exportURL(for rendition: WatermarkRendition, recipientName: String) async -> URL? {
        do {
            let directory = try beginTemporaryExportSession()
            return try await renderExport(rendition, recipientName: recipientName, into: directory)
        } catch {
            cleanupTemporaryExports()
            errorMessage = "The watermarked PDF could not be prepared."
            return nil
        }
    }

    func exportURLs(for issuance: WatermarkIssuance) async -> [URL] {
        do {
            let directory = try beginTemporaryExportSession()
            var urls: [URL] = []
            for rendition in issuance.renditions {
                try await urls.append(renderExport(
                    rendition,
                    recipientName: issuance.recipientNameSnapshot,
                    into: directory
                ))
            }
            return urls
        } catch {
            cleanupTemporaryExports()
            errorMessage = "The watermarked PDFs could not be prepared."
            return []
        }
    }

    func cleanupTemporaryExports() {
        guard let temporaryExportDirectory else { return }
        try? FileManager.default.removeItem(at: temporaryExportDirectory)
        self.temporaryExportDirectory = nil
    }

    private func beginTemporaryExportSession() throws -> URL {
        cleanupTemporaryExports()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryExportDirectory = directory
        return directory
    }

    private func renderExport(
        _ rendition: WatermarkRendition,
        recipientName: String,
        into directory: URL
    ) async throws -> URL {
        let filename = ExportFilenameSanitizer.sanitize(
            "\(rendition.originalNameSnapshot) - \(recipientName) - v\(rendition.version)"
        )
        let url = directory.appendingPathComponent(filename).appendingPathExtension("pdf")
        let job = PDFRenderJob(
            pages: rendition.pages.sorted(by: { $0.index < $1.index }).map {
                PDFRenderPage(id: $0.id, assetReference: $0.watermarked)
            },
            pageSize: .original,
            fitMode: .fit,
            marginPoints: 0,
            outputURL: url
        )
        return try await BulkPDFRenderer(assetStore: storage).renderPDF(job: job, progress: { _ in })
    }

    private func persistWatermarkRenditionTrash(id: UUID, deletedAt: Date?) async -> Bool {
        guard let issuance = issuance(containing: id) else { return false }
        let updatedRenditions = issuance.renditions.map { item in
            guard item.id == id else { return item }
            return WatermarkRendition(
                id: item.id,
                documentId: item.documentId,
                issuanceId: item.issuanceId,
                originalNameSnapshot: item.originalNameSnapshot,
                version: item.version,
                config: item.config,
                pages: item.pages,
                createdAt: item.createdAt,
                deletedAt: deletedAt
            )
        }
        let updated = WatermarkIssuance(
            id: issuance.id,
            recipientId: issuance.recipientId,
            recipientNameSnapshot: issuance.recipientNameSnapshot,
            purpose: issuance.purpose,
            templateConfig: issuance.templateConfig,
            renditions: updatedRenditions,
            createdAt: issuance.createdAt
        )
        do {
            try await storage.saveWatermarkIssuance(updated)
            await load()
            return true
        } catch {
            errorMessage = deletedAt == nil ? "Could not restore copy." : "Could not move copy to Trash."
            return false
        }
    }

    func recipient(named rawName: String) -> WatermarkRecipient? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return watermarkRecipients.first { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }
    }

    func createWatermarkedCopies(
        request: WatermarkCopyRequest,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> WatermarkIssuance? {
        let name = request.recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter a recipient before creating copies."
            return nil
        }
        let timestamp = Date()
        let recipient = recipient(named: name) ?? WatermarkRecipient(
            id: UUID(), displayName: name, createdAt: timestamp, updatedAt: timestamp
        )
        do {
            let issuance = try await watermarkIssuanceService.createCopies(
                documents: documents(forIDs: request.documentIDs),
                recipient: recipient,
                purpose: request.purpose,
                templateConfig: request.templateConfig,
                watermarkImageData: request.imageData,
                progress: progress
            )
            await load()
            return issuance
        } catch WatermarkIssuanceError.missingPurpose {
            errorMessage = "Add a purpose or remove the {purpose} field from the watermark."
        } catch WatermarkIssuanceError.invisibleWatermark {
            errorMessage = "Add at least one visible watermark layer."
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = "Copies could not be created. Your originals and watermark design are unchanged."
        }
        return nil
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

    func trashWatermarkRendition(_ rendition: WatermarkRendition) async -> Bool {
        await moveToTrash(.rendition(rendition.id))
    }

    func restoreWatermarkRendition(_ rendition: WatermarkRendition) async -> Bool {
        await restoreManually(.rendition(rendition.id))
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
            case .rendition(let id):
                guard await persistWatermarkRenditionTrash(id: id, deletedAt: .now) else { return false }
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
            case .rendition(let id):
                guard await persistWatermarkRenditionTrash(id: id, deletedAt: nil) else { return false }
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

    func deletePermanently(_ document: StoredDocument) async -> Bool {
        let removal: RemovedWatermarkCopies
        do {
            // Derived metadata is removed first so a process interruption can
            // never leave a visible copy pointing at a permanently deleted
            // original. Assets remain available until the original delete
            // succeeds, allowing metadata rollback on an archive failure.
            removal = try await permanentlyRemoveWatermarkCopies(documentIDs: [document.id])
        } catch {
            errorMessage = "Could not remove related watermarked copies. The original was not deleted."
            return false
        }
        do {
            try await archive.deletePermanently(documentId: document.id)
        } catch {
            try? await restoreWatermarkCopies(removal)
            errorMessage = "Could not delete document. Try again."
            return false
        }
        return await finishPermanentRemoval(removal, deletedItem: "Document")
    }

    func deletePermanently(_ folder: Folder) async -> Bool {
        let documentIDs = Set((documentsByFolder[folder.id] ?? []).map(\.id))
        let removal: RemovedWatermarkCopies
        do {
            removal = try await permanentlyRemoveWatermarkCopies(documentIDs: documentIDs)
        } catch {
            errorMessage = "Could not remove related watermarked copies. The folder was not deleted."
            return false
        }
        do {
            try await archive.deletePermanently(folderId: folder.id)
        } catch {
            try? await restoreWatermarkCopies(removal)
            errorMessage = "Could not delete folder. Try again."
            return false
        }
        return await finishPermanentRemoval(removal, deletedItem: "Folder")
    }

    func deletePermanently(_ rendition: WatermarkRendition) async -> Bool {
        do {
            let removal = try await permanentlyRemoveWatermarkCopies(renditionIDs: [rendition.id])
            return await finishPermanentRemoval(removal, deletedItem: "Copy")
        } catch {
            errorMessage = "Could not permanently delete copy. Try again."
            return false
        }
    }

    private func permanentlyRemoveWatermarkCopies(
        documentIDs: Set<UUID> = [],
        renditionIDs: Set<UUID> = []
    ) async throws -> RemovedWatermarkCopies {
        var originals: [WatermarkIssuance] = []
        var candidateAssets: [UUID: AssetReference] = [:]
        for issuance in watermarkIssuances {
            let removed = issuance.renditions.filter {
                documentIDs.contains($0.documentId) || renditionIDs.contains($0.id)
            }
            guard !removed.isEmpty else { continue }
            let remaining = issuance.renditions.filter { item in !removed.contains(where: { $0.id == item.id }) }
            do {
                originals.append(issuance)
                if remaining.isEmpty {
                    try await storage.removeWatermarkIssuance(id: issuance.id)
                } else {
                    try await storage.saveWatermarkIssuance(WatermarkIssuance(
                        id: issuance.id,
                        recipientId: issuance.recipientId,
                        recipientNameSnapshot: issuance.recipientNameSnapshot,
                        purpose: issuance.purpose,
                        templateConfig: issuance.templateConfig,
                        renditions: remaining,
                        createdAt: issuance.createdAt
                    ))
                }
                for page in removed.flatMap(\.pages) {
                    candidateAssets[page.watermarked.id] = page.watermarked
                }
                for logo in removed.compactMap({ $0.config.image?.assetRef }) {
                    candidateAssets[logo.id] = logo
                }
            } catch {
                try? await restoreWatermarkCopies(RemovedWatermarkCopies(
                    originalIssuances: originals,
                    candidateAssets: []
                ))
                throw error
            }
        }
        return RemovedWatermarkCopies(
            originalIssuances: originals,
            candidateAssets: Array(candidateAssets.values)
        )
    }

    private func restoreWatermarkCopies(_ removal: RemovedWatermarkCopies) async throws {
        for issuance in removal.originalIssuances {
            try await storage.saveWatermarkIssuance(issuance)
        }
    }

    private func finishPermanentRemoval(
        _ removal: RemovedWatermarkCopies,
        deletedItem: String
    ) async -> Bool {
        do {
            let referencedIDs = try await storage.referencedAssetIDs()
            for asset in removal.candidateAssets where !referencedIDs.contains(asset.id) {
                try await storage.removeAsset(asset)
            }
            await load()
            return true
        } catch {
            await load()
            errorMessage = "\(deletedItem) was deleted, but unused storage could not be reclaimed."
            return false
        }
    }

    func purgeExpiredTrash() async {
        guard !isPurging else { return }
        isPurging = true
        defer { isPurging = false }

        let didPurge = await archive.purgeExpiredTrash()
        let expiredRenditionIDs = Set(trashedWatermarkRenditions.compactMap { rendition -> UUID? in
            guard let deletedAt = rendition.deletedAt else { return nil }
            return ArchiveService.retentionDaysRemaining(deletedAt: deletedAt, now: .now) == 0 ? rendition.id : nil
        })
        if !expiredRenditionIDs.isEmpty {
            do {
                let removal = try await permanentlyRemoveWatermarkCopies(renditionIDs: expiredRenditionIDs)
                _ = await finishPermanentRemoval(removal, deletedItem: "Expired copies")
            } catch {
                errorMessage = "Expired copies could not be purged."
            }
        }
        if didPurge || !expiredRenditionIDs.isEmpty {
            await load()
        }
    }
}

// MARK: - Tags

extension LibraryStore {
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
}

public struct LibraryExportDocumentLoader: ExportDocumentLoading, Sendable {
    private let loader: @Sendable (Set<UUID>) async throws -> [StoredDocument]

    public init(loader: @escaping @Sendable (Set<UUID>) async throws -> [StoredDocument]) {
        self.loader = loader
    }

    public func documents(ids: Set<UUID>) async throws -> [StoredDocument] {
        try await loader(ids)
    }
}
