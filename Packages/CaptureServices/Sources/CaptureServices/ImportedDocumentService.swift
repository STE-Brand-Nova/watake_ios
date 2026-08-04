import CryptoKit
import Foundation
import WatakeDomain

public enum ImportSaveError: Error, Equatable, Sendable {
    case targetFolderMissing
    case targetFolderTrashed
    case emptyImport
    case cacheUnavailable
    case thumbnailFailed
}

public struct ImportedDocumentFactory: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func makeDocument(folderID: UUID, name: String, orderIndex: Int, pages: [ImportedPage]) throws -> StoredDocument {
        guard !pages.isEmpty else { throw ImportSaveError.emptyImport }
        let id = UUID()
        let timestamp = now()
        let documentPages = pages.enumerated().map { index, page in
            let pageID = UUID()
            return DocumentPage(
                id: pageID,
                index: index,
                source: asset(
                    data: page.sourceData,
                    documentID: id,
                    pageID: pageID,
                    kind: "source",
                    metadata: SourceMetadata(mediaType: page.sourceMediaType, fileExtension: page.sourceFileExtension)
                ),
                rectified: page.rectifiedJPEG.map {
                    asset(
                        data: $0,
                        documentID: id,
                        pageID: pageID,
                        kind: "rectified",
                        metadata: SourceMetadata(mediaType: "image/jpeg", fileExtension: "jpg")
                    )
                }
            )
        }
        let document = StoredDocument(
            id: id, folderId: folderID, name: name, createdAt: timestamp, updatedAt: timestamp,
            orderIndex: orderIndex, pages: documentPages
        )
        try document.validate()
        return document
    }

    private func asset(
        data: Data,
        documentID: UUID,
        pageID: UUID,
        kind: String,
        metadata: SourceMetadata
    ) -> AssetReference {
        AssetReference(
            id: UUID(),
            relativePath: [
                "documents/\(documentID.uuidString.lowercased())",
                "pages/\(pageID.uuidString.lowercased())",
                "\(kind).\(metadata.fileExtension)"
            ].joined(separator: "/"),
            sha256Hex: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            byteSize: data.count,
            mediaType: metadata.mediaType
        )
    }
}

private struct SourceMetadata: Sendable {
    let mediaType: String
    let fileExtension: String
}

/// Staged capture/import commit: assets write atomically, metadata follows
/// only after every source/derivative validates, and cancellation/failure
/// removes all assets already committed by this transaction.
public struct ImportedDocumentService: Sendable {
    private let repository: any DocumentRepository
    private let assetStore: any DocumentAssetStore
    private let serialiser: FolderScanOperationSerialiser
    private let factory: ImportedDocumentFactory

    public init(
        repository: any DocumentRepository,
        assetStore: any DocumentAssetStore,
        serialiser: FolderScanOperationSerialiser,
        factory: ImportedDocumentFactory = ImportedDocumentFactory()
    ) {
        self.repository = repository
        self.assetStore = assetStore
        self.serialiser = serialiser
        self.factory = factory
    }

    public func save(pages: [ImportedPage], into folderID: UUID, named name: String) async throws -> StoredDocument {
        try await serialiser.perform(for: folderID) {
            try Task.checkCancellation()
            guard let folder = try await repository.folder(id: folderID) else { throw ImportSaveError.targetFolderMissing }
            guard folder.deletedAt == nil else { throw ImportSaveError.targetFolderTrashed }
            let order = try await (repository.documents(in: folderID).map(\.orderIndex).max() ?? -1) + 1
            let document = try factory.makeDocument(folderID: folderID, name: name, orderIndex: order, pages: pages)
            var saved: [AssetReference] = []
            do {
                for page in document.pages {
                    try Task.checkCancellation()
                    saved.append(page.source)
                    try await assetStore.saveAsset(pages[page.index].sourceData, reference: page.source)
                    if let rectified = page.rectified, let bytes = pages[page.index].rectifiedJPEG {
                        saved.append(rectified)
                        try await assetStore.saveAsset(bytes, reference: rectified)
                    }
                }
                try Task.checkCancellation()
                try await repository.saveDocument(document)
                return document
            } catch {
                for reference in saved.reversed() {
                    try? await assetStore.removeAsset(reference)
                }
                throw error
            }
        }
    }

    public func save(
        pages: [ImportedPage],
        grouping: GalleryGrouping,
        into folderID: UUID,
        named name: String
    ) async throws -> [StoredDocument] {
        switch grouping {
        case .oneDocument:
            return try await [save(pages: pages, into: folderID, named: name)]
        case .separateDocuments:
            var documents: [StoredDocument] = []
            documents.reserveCapacity(pages.count)
            do {
                for (index, page) in pages.enumerated() {
                    try Task.checkCancellation()
                    try await documents.append(save(pages: [page], into: folderID, named: "\(name) \(index + 1)"))
                }
                return documents
            } catch {
                for document in documents.reversed() {
                    let trashed = StoredDocument(
                        id: document.id,
                        folderId: document.folderId,
                        name: document.name,
                        createdAt: document.createdAt,
                        updatedAt: document.updatedAt,
                        orderIndex: document.orderIndex,
                        pages: document.pages,
                        deletedAt: Date(),
                        tagIds: document.tagIds,
                        watermarkPresetId: document.watermarkPresetId
                    )
                    try? await repository.saveDocument(trashed)
                    try? await repository.deleteDocument(id: document.id)
                }
                throw error
            }
        }
    }
}
