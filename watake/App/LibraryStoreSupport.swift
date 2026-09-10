import CaptureServices
import DocumentProcessing
import DocumentViewerFeature
import Foundation
import WatakeDomain
import WatakeStorage

actor AnnotationAwareThumbnailLoader: DocumentPageThumbnailLoading {
    private let base: any DocumentPageThumbnailLoading
    private let assetStore: any DocumentAssetStore
    private let renderer: any PageAnnotationRendering

    init(base: any DocumentPageThumbnailLoading, assetStore: any DocumentAssetStore) {
        self.base = base
        self.assetStore = assetStore
        renderer = PageAnnotationCompositor(assetStore: assetStore)
    }

    func thumbnail(for page: DocumentPage) async throws -> Data {
        guard !page.annotations.isEmpty else { return try await base.thumbnail(for: page) }
        let source: Data = if let rectified = page.rectified, let data = try? await assetStore.readAsset(rectified) {
            data
        } else {
            try await assetStore.readAsset(page.source)
        }
        return try await renderer.renderJPEG(
            sourceData: source,
            annotations: page.annotations,
            maximumPixelDimension: 224,
            quality: 0.85
        )
    }
}

@MainActor
extension LibraryStore {
    var documentEditingStore: any DocumentEditingStore {
        storage
    }

    func documentEditorDidPersist(_ document: StoredDocument, isCopy: Bool) {
        if isCopy {
            selectedFolderID = document.folderId
            selectedDocumentID = document.id
            mostRecentlyUsedFolder = document.folderId
        }
        Task { await load() }
    }

    func watermarkPreviewData(for document: StoredDocument) async -> Data? {
        guard let page = document.pages.min(by: { $0.index < $1.index }) else { return nil }
        guard let data = try? await storage.readAsset(page.rectified ?? page.source) else { return nil }
        guard !page.annotations.isEmpty else { return data }
        return try? await PageAnnotationCompositor(assetStore: storage).renderJPEG(
            sourceData: data,
            annotations: page.annotations,
            maximumPixelDimension: 2048,
            quality: 0.92
        )
    }
}

enum DocumentLayout: String, CaseIterable {
    case list
    case grid
}

/// Session-only offer for restoring the latest item sent to Trash. The item is
/// already durably soft-deleted; this only controls temporary Library UI.
enum TrashItemID: Equatable, Sendable {
    case document(UUID)
    case folder(UUID)
    case rendition(UUID)
}

struct PendingTrashUndo: Equatable, Sendable {
    let id: UUID
    let item: TrashItemID
}

struct WatermarkCopyRequest: Sendable {
    let documentIDs: Set<UUID>
    let recipientName: String
    let purpose: String?
    let templateConfig: WatermarkConfig
    let imageData: Data?
}

struct WatermarkFlowPresentation: Identifiable {
    let id = UUID()
    let documents: [StoredDocument]
    let sourceImageData: Data
}

struct ViewerWatermarkTransition: Equatable {
    private(set) var pendingDocumentIDs: Set<UUID>?

    mutating func request(documentID: UUID, viewerIsPresentedModally: Bool) -> Set<UUID>? {
        let documentIDs: Set<UUID> = [documentID]
        guard viewerIsPresentedModally else { return documentIDs }
        pendingDocumentIDs = documentIDs
        return nil
    }

    mutating func takePendingAfterViewerDismissal() -> Set<UUID>? {
        defer { pendingDocumentIDs = nil }
        return pendingDocumentIDs
    }
}

enum ViewerCopiesRequest: Equatable {
    case all
    case rendition(documentID: UUID, renditionID: UUID)
}

struct ViewerCopiesTransition: Equatable {
    private(set) var pendingRequest: ViewerCopiesRequest?

    mutating func request(
        _ request: ViewerCopiesRequest,
        viewerIsPresentedModally: Bool
    ) -> ViewerCopiesRequest? {
        guard viewerIsPresentedModally else { return request }
        pendingRequest = request
        return nil
    }

    mutating func takePendingAfterViewerDismissal() -> ViewerCopiesRequest? {
        defer { pendingRequest = nil }
        return pendingRequest
    }
}

enum ViewerDocumentAction: Equatable {
    case rename(UUID)
    case move(UUID)
    case export(StoredDocument)
    case delete(UUID)

    var documentID: UUID {
        switch self {
        case .rename(let id), .move(let id), .delete(let id): id
        case .export(let document): document.id
        }
    }
}

struct ViewerDocumentActionTransition: Equatable {
    private(set) var pendingAction: ViewerDocumentAction?

    mutating func request(
        _ action: ViewerDocumentAction,
        viewerIsPresentedModally: Bool
    ) -> ViewerDocumentAction? {
        guard viewerIsPresentedModally else { return action }
        pendingAction = action
        return nil
    }

    mutating func takePendingAfterViewerDismissal() -> ViewerDocumentAction? {
        defer { pendingAction = nil }
        return pendingAction
    }
}

struct WatermarkCopyNavigationRequest: Equatable, Sendable {
    let documentID: UUID
    let renditionID: UUID
}

struct ResolvedWatermarkCopyNavigation: Equatable, Sendable {
    let request: WatermarkCopyNavigationRequest
    let issuance: WatermarkIssuance
    let rendition: WatermarkRendition
}

func makeWatermarkCopySummaryIndex(
    from issuances: [WatermarkIssuance]
) -> [UUID: [DocumentWatermarkedCopySummary]] {
    var index: [UUID: [DocumentWatermarkedCopySummary]] = [:]
    for issuance in issuances {
        for rendition in issuance.renditions where rendition.deletedAt == nil {
            index[rendition.documentId, default: []].append(DocumentWatermarkedCopySummary(
                id: rendition.id,
                recipientName: issuance.recipientNameSnapshot,
                version: rendition.version,
                createdAt: rendition.createdAt
            ))
        }
    }
    return index
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

struct RemovedWatermarkCopies {
    let originalIssuances: [WatermarkIssuance]
    let candidateAssets: [AssetReference]
}

/// Degraded thumbnail path used only if `ThumbnailCache` construction fails.
struct RawAssetThumbnailFallback: DocumentPageThumbnailLoading {
    let assetStore: any DocumentAssetStore

    func thumbnail(for page: DocumentPage) async throws -> Data {
        if let rectified = page.rectified, let data = try? await assetStore.readAsset(rectified) {
            return data
        }
        return try await assetStore.readAsset(page.source)
    }
}
