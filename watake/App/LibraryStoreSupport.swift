import CaptureServices
import DocumentViewerFeature
import Foundation
import WatakeDomain

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
