import ArchiveServices
import CaptureServices
import Foundation
import WatakeDomain

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

    var trashedDocuments: [StoredDocument] {
        documentsByFolder.values.flatMap(\.self).filter { $0.deletedAt != nil }
    }

    var activeDocuments: [StoredDocument] {
        documentsByFolder.values.flatMap(\.self)
            .filter { document in
                document.deletedAt == nil && folder(for: document.folderId)?.deletedAt == nil
            }
    }

    func createFolder(
        name: String,
        colorHex: String = ArchiveTagPalette.colors[8],
        iconId: String = FolderIconCatalog.defaultIdentifier
    ) async -> Folder? {
        do {
            let folder = try await archive.createFolder(name: name, colorHex: colorHex, iconId: iconId)
            await load()
            return folder
        } catch {
            errorMessage = "Could not create folder. Try again."
            return nil
        }
    }

    @discardableResult
    func updateFolder(_ folder: Folder, name: String, colorHex: String, iconId: String) async -> Bool {
        await run {
            _ = try await archive.updateFolder(
                folderId: folder.id,
                name: name,
                colorHex: colorHex,
                iconId: iconId
            )
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

    @discardableResult
    private func run(_ operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
            await load()
            return true
        } catch is CancellationError {
            // User cancellation is intentionally silent.
            return false
        } catch {
            errorMessage = "Could not save changes. Your original pages are unchanged."
            return false
        }
    }
}
