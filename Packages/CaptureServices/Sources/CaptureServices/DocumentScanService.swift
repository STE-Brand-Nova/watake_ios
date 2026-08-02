import CryptoKit
import Foundation
import WatakeDomain

/// Builds a valid immutable document record from encoded scanner pages.
public struct ScannedDocumentFactory: Sendable {
    private let now: @Sendable () -> Date

    public init(
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.now = now
    }

    public func makeDocument(
        folderID: UUID,
        name: String,
        orderIndex: Int,
        pages: [ScannedPage]
    ) throws -> StoredDocument {
        guard !pages.isEmpty else {
            throw DocumentScanSaveError.emptyScan
        }

        let documentID = UUID()
        let timestamp = now()
        let documentPages = pages.enumerated().map { index, page in
            DocumentPage(
                id: UUID(),
                index: index,
                source: makeAssetReference(
                    jpegData: page.jpegData,
                    documentID: documentID
                )
            )
        }
        let document = StoredDocument(
            id: documentID,
            folderId: folderID,
            name: name,
            createdAt: timestamp,
            updatedAt: timestamp,
            orderIndex: orderIndex,
            pages: documentPages
        )
        try document.validate()
        return document
    }

    private func makeAssetReference(
        jpegData: Data,
        documentID: UUID
    ) -> AssetReference {
        let pageID = UUID()
        return AssetReference(
            id: pageID,
            relativePath: "documents/\(documentID.uuidString.lowercased())/source/\(pageID.uuidString.lowercased()).jpg",
            sha256Hex: SHA256.hash(data: jpegData).map { String(format: "%02x", $0) }.joined(),
            byteSize: jpegData.count,
            mediaType: "image/jpeg"
        )
    }
}

/// Foundation save seam, not an app-wired scanner feature. The current Capture
/// route has no valid folder/name input or production `DocumentPageCapturing`
/// bridge, so app composition must wait for that feature state.
public struct DocumentScanService: DocumentScanning, Sendable {
    private let dependencies: ScanDependencies
    private let operationSerialiser: FolderScanOperationSerialiser

    public init(
        pageCapturer: any DocumentPageCapturing,
        repository: any DocumentRepository,
        assetStore: any DocumentAssetStore,
        operationSerialiser: FolderScanOperationSerialiser,
        factory: ScannedDocumentFactory = ScannedDocumentFactory()
    ) {
        dependencies = ScanDependencies(
            pageCapturer: pageCapturer,
            repository: repository,
            assetStore: assetStore,
            factory: factory
        )
        self.operationSerialiser = operationSerialiser
    }

    public func scanDocument(into folderId: UUID, named name: String) async throws -> StoredDocument {
        try await operationSerialiser.perform(for: folderId) { [dependencies] in
            try await Self.saveScannedDocument(
                into: folderId,
                named: name,
                dependencies: dependencies
            )
        }
    }

    private static func saveScannedDocument(
        into folderId: UUID,
        named name: String,
        dependencies: ScanDependencies
    ) async throws -> StoredDocument {
        try Task.checkCancellation()
        guard let folder = try await dependencies.repository.folder(id: folderId) else {
            throw DocumentScanSaveError.targetFolderMissing
        }
        guard folder.deletedAt == nil else {
            throw DocumentScanSaveError.targetFolderTrashed
        }

        let pages: [ScannedPage]
        do {
            pages = try await dependencies.pageCapturer.capturePages()
        } catch NativeDocumentScannerError.cancelled {
            throw CancellationError()
        }
        try Task.checkCancellation()

        let existingDocuments = try await dependencies.repository.documents(in: folderId)
        let nextOrderIndex = (existingDocuments.map(\.orderIndex).max() ?? -1) + 1
        let document = try dependencies.factory.makeDocument(
            folderID: folderId,
            name: name,
            orderIndex: nextOrderIndex,
            pages: pages
        )

        var stagedAssets: [AssetReference] = []
        do {
            for page in document.pages {
                stagedAssets.append(page.source)
                try await dependencies.assetStore.saveAsset(pages[page.index].jpegData, reference: page.source)
            }
            try Task.checkCancellation()
            try await dependencies.repository.saveDocument(document)
            return document
        } catch {
            for reference in stagedAssets.reversed() {
                try? await dependencies.assetStore.removeAsset(reference)
            }
            throw error
        }
    }

    private struct ScanDependencies: Sendable {
        let pageCapturer: any DocumentPageCapturing
        let repository: any DocumentRepository
        let assetStore: any DocumentAssetStore
        let factory: ScannedDocumentFactory
    }
}
