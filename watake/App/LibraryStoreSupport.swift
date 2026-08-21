import CaptureServices
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
