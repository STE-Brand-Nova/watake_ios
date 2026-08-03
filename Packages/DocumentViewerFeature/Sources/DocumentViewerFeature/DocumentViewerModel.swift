import Foundation
import Observation
import WatakeDomain

/// Feature model for reopening one saved document and browsing its ordered
/// pages. Owns no routing state — callers pass a `DocumentID` (`UUID`) at
/// `init` and keep the model instance alive above any compact/regular/
/// expanded layout switch so the selected document/page survives width
/// changes.
@MainActor
@Observable
public final class DocumentViewerModel {
    public private(set) var state: DocumentViewerState = .loading

    private let documentID: UUID
    private let loader: any DocumentPageAssetLoading
    private let thumbnailLoader: DocumentPageThumbnailLoader
    private var loadTask: Task<Void, Never>?
    private var assetTask: Task<Void, Never>?

    public init(documentID: UUID, loader: any DocumentPageAssetLoading) {
        self.documentID = documentID
        self.loader = loader
        thumbnailLoader = DocumentPageThumbnailLoader(loader: loader)
    }

    /// Loads (or reloads) the document. Cancels any in-flight load first so a
    /// rapid re-entry (e.g. switching documents quickly) cannot let a stale
    /// result overwrite a newer one.
    public func load() {
        loadTask?.cancel()
        assetTask?.cancel()
        state = .loading
        loadTask = Task { [weak self] in
            await self?.performLoad()
        }
    }

    /// Starts the initial load only if one has never been started. Call from
    /// a view's `.task` so a compact/regular reflow (which destroys and
    /// recreates the viewer surface, re-running `.task`) never resets an
    /// already-loaded document back to its first page. Loading only ever
    /// stops via explicit `cancel()`, not this call.
    public func loadIfNeeded() {
        guard case .loading = state, loadTask == nil else { return }
        load()
    }

    /// Selects a different page within the currently loaded document and
    /// loads its display asset. No-op if the page is already selected, the
    /// document isn't loaded, or the page isn't part of it.
    public func select(pageID: UUID) {
        guard case .content(var content) = state else { return }
        guard content.selectedPageID != pageID, content.pages.contains(where: { $0.id == pageID }) else { return }
        content.selectedPageID = pageID
        content.pageAsset = .loading
        state = .content(content)
        loadPageAsset(pageID: pageID)
    }

    /// Retries whatever most recently failed: the document load, or the
    /// selected page's asset load.
    public func retry() {
        switch state {
        case .failure, .empty:
            load()
        case .content(let content):
            if case .failure = content.pageAsset {
                loadPageAsset(pageID: content.selectedPageID)
            }
        case .loading:
            break
        }
    }

    /// Cancels any in-flight work without changing the published state.
    /// Call from `onDisappear` so a dismissed viewer doesn't keep loading.
    public func cancel() {
        loadTask?.cancel()
        assetTask?.cancel()
    }

    /// Loads one page's downsampled, bounded-concurrency thumbnail for the
    /// page rail, independent of the main preview's selected-page asset load.
    public func loadThumbnailData(for page: DocumentPage) async throws -> Data {
        try await thumbnailLoader.thumbnail(for: page)
    }

    /// Test-only synchronization point: awaits any in-flight document/asset
    /// load so tests can assert on settled state without polling.
    func waitUntilIdle() async {
        await loadTask?.value
        await assetTask?.value
    }

    private func performLoad() async {
        do {
            guard let document = try await loader.document(id: documentID) else {
                guard !Task.isCancelled else { return }
                state = .empty
                return
            }
            guard !Task.isCancelled else { return }
            let pages = document.pages.sorted { $0.index < $1.index }
            guard let firstPage = pages.first else {
                state = .empty
                return
            }
            state = .content(
                DocumentViewerContent(document: document, pages: pages, selectedPageID: firstPage.id, pageAsset: .loading)
            )
            loadPageAsset(pageID: firstPage.id)
        } catch is CancellationError {
            // Superseded or dismissed load: leave prior state untouched.
        } catch {
            guard !Task.isCancelled else { return }
            state = .failure(.documentUnavailable)
        }
    }

    private func loadPageAsset(pageID: UUID) {
        assetTask?.cancel()
        assetTask = Task { [weak self] in
            await self?.performLoadPageAsset(pageID: pageID)
        }
    }

    private func performLoadPageAsset(pageID: UUID) async {
        guard case .content(let content) = state, let page = content.pages.first(where: { $0.id == pageID }) else {
            return
        }
        do {
            let (data, isRectified) = try await readDisplayAsset(page: page)
            apply(pageID: pageID) {
                $0.pageAsset = .loaded(data)
                $0.isPageAssetRectified = isRectified
            }
        } catch is CancellationError {
            // Superseded selection or dismissed load: leave prior state untouched.
        } catch {
            guard !Task.isCancelled else { return }
            apply(pageID: pageID) { $0.pageAsset = .failure(.pageAssetUnavailable) }
        }
    }

    /// Prefers the rectified derivative; if it's missing or corrupt, falls
    /// back to the immutable source rather than surfacing an error while a
    /// healthy source still exists.
    private func readDisplayAsset(page: DocumentPage) async throws -> (data: Data, isRectified: Bool) {
        if let rectified = page.rectified {
            do {
                return try await (loader.readAsset(rectified), true)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Fall through to the source below.
            }
        }
        return try await (loader.readAsset(page.source), false)
    }

    /// Applies a mutation only if the selection hasn't moved on since the
    /// asset load for `pageID` started, so a slow load for a page the user
    /// already navigated away from can never clobber the current selection.
    private func apply(pageID: UUID, _ mutate: (inout DocumentViewerContent) -> Void) {
        guard !Task.isCancelled, case .content(var content) = state, content.selectedPageID == pageID else {
            return
        }
        mutate(&content)
        state = .content(content)
    }
}
