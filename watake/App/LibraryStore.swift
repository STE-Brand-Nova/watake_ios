import ArchiveServices
import CaptureServices
import Foundation
import Observation
import WatakeDomain
import WatakeStorage

@MainActor
@Observable
final class LibraryStore {
    private let storage: WatakeFileStorage
    private let archive: ArchiveService
    private let importer: ImportedDocumentService
    private let thumbnailCache: ThumbnailCache?

    private(set) var folders: [Folder] = []
    private(set) var documentsByFolder: [UUID: [StoredDocument]] = [:]
    private(set) var tags: [Tag] = []
    var errorMessage: String?
    var isLoading = false

    init() {
        let storage = WatakeFileStorage(
            rootResolver: ApplicationSupportRootResolver(),
            protectionApplier: UntilFirstUnlockFileProtection(),
            encryptionKeyStore: KeychainEncryptionKeyStore(service: "com.watake.assets")
        )
        self.storage = storage
        archive = ArchiveService(repository: storage)
        importer = ImportedDocumentService(repository: storage, assetStore: storage, serialiser: FolderScanOperationSerialiser())
        thumbnailCache = try? ThumbnailCache()
    }

    var activeFolders: [Folder] {
        folders.filter { $0.deletedAt == nil }
    }

    var trashedFolders: [Folder] {
        folders.filter { $0.deletedAt != nil }
    }

    func documents(in folder: Folder) -> [StoredDocument] {
        (documentsByFolder[folder.id] ?? []).filter { $0.deletedAt == nil }.sorted { $0.orderIndex < $1.orderIndex }
    }

    var trashedDocuments: [StoredDocument] {
        documentsByFolder.values.flatMap(\.self).filter { $0.deletedAt != nil }
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

    func trashDocument(_ document: StoredDocument) async {
        await run { try await archive.moveToTrash(documentId: document.id) }
    }

    func restoreDocument(_ document: StoredDocument) async {
        await run { try await archive.restore(documentId: document.id) }
    }

    func trashFolder(_ folder: Folder) async {
        await run { try await archive.moveToTrash(folderId: folder.id) }
    }

    func restoreFolder(_ folder: Folder) async {
        await run { try await archive.restore(folderId: folder.id) }
    }

    func reorder(folder: Folder, documents: [StoredDocument]) async {
        await run { try await archive.reorderDocuments(in: folder.id, ids: documents.map(\.id)) }
    }

    func createTag(label: String, colorHex: String) async {
        await run { _ = try await archive.createTag(label: label, colorHex: colorHex) }
    }

    func assign(tagIds: [UUID], document: StoredDocument) async {
        await run { _ = try await archive.assign(tagIds: tagIds, to: document.id) }
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
