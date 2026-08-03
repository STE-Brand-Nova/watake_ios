import Foundation
import WatakeDomain

/// Prefers the derived rectified asset when present; falls back to the
/// immutable source, per `docs/data-model.md`.
extension DocumentPage {
    public var displayAsset: AssetReference {
        rectified ?? source
    }

    /// `true` when the page is currently showing its rectified derivative
    /// rather than the immutable source.
    public var isShowingRectified: Bool {
        rectified != nil
    }
}

/// Privacy-safe, typed viewer failures. Never carry document names, OCR text,
/// file paths, or raw framework error payloads.
public enum DocumentViewerError: Error, Equatable, Sendable {
    case documentUnavailable
    case pageAssetUnavailable
    case pageAssetUndecodable
}

/// Load state for the currently selected page's image data.
public enum PageAssetState: Equatable, Sendable {
    case loading
    case loaded(Data)
    case failure(DocumentViewerError)
}

/// A loaded document ready to display, with its pages ordered by `index`.
public struct DocumentViewerContent: Equatable, Sendable {
    public let document: StoredDocument
    public let pages: [DocumentPage]
    public var selectedPageID: UUID
    public var pageAsset: PageAssetState

    /// Whether `pageAsset` is actually showing the rectified derivative, as
    /// opposed to `DocumentPage.isShowingRectified` which only reflects that
    /// metadata references one. These can disagree when the rectified asset
    /// failed to load and the model fell back to the immutable source.
    public var isPageAssetRectified: Bool

    public init(
        document: StoredDocument, pages: [DocumentPage], selectedPageID: UUID, pageAsset: PageAssetState,
        isPageAssetRectified: Bool = true
    ) {
        self.document = document
        self.pages = pages
        self.selectedPageID = selectedPageID
        self.pageAsset = pageAsset
        self.isPageAssetRectified = isPageAssetRectified
    }

    public var selectedIndex: Int? {
        pages.firstIndex { $0.id == selectedPageID }
    }

    public var selectedPage: DocumentPage? {
        selectedIndex.map { pages[$0] }
    }
}

/// Explicit viewer states. There is no separate "cancelled" case: an
/// in-flight load that is superseded or cancelled leaves the prior state
/// untouched instead of publishing a transient result (mirrors
/// `LibraryStore`'s "user cancellation is intentionally silent" convention).
public enum DocumentViewerState: Equatable, Sendable {
    case loading
    case content(DocumentViewerContent)
    case empty
    case failure(DocumentViewerError)
}
