import Foundation
import Testing
import WatakeDomain
@testable import DocumentViewerFeature

@MainActor
@Suite("DocumentViewerModel")
struct DocumentViewerModelTests {
    @Test("orders pages by index and auto-loads the first page's asset")
    func loadOrdersPagesAndAutoLoadsFirstPageAsset() async {
        let sourceFirst = makeAssetReference()
        let sourceSecond = makeAssetReference()
        let pageIndex1 = makePage(index: 1, source: sourceSecond)
        let pageIndex0 = makePage(index: 0, source: sourceFirst)
        // Persisted out of order on purpose: the model must not trust storage order.
        let document = makeDocument(pages: [pageIndex1, pageIndex0])

        let loader = FakeLoader()
        await loader.setDocument(document)
        await loader.setAsset(Data("first".utf8), for: sourceFirst)

        let model = DocumentViewerModel(documentID: document.id, loader: loader, thumbnailLoader: FakeThumbnailLoader())
        model.load()
        await model.waitUntilIdle()

        guard case .content(let content) = model.state else {
            Issue.record("expected content state")
            return
        }
        #expect(content.pages.map(\.index) == [0, 1])
        #expect(content.selectedPageID == pageIndex0.id)
        #expect(content.pageAsset == .loaded(Data("first".utf8)))
    }

    @Test("a document that no longer exists resolves to empty")
    func loadMissingDocumentIsEmpty() async {
        let loader = FakeLoader()
        let model = DocumentViewerModel(documentID: UUID(), loader: loader, thumbnailLoader: FakeThumbnailLoader())

        model.load()
        await model.waitUntilIdle()

        #expect(model.state == .empty)
    }

    @Test("a document load error resolves to a privacy-safe failure")
    func loadErrorIsFailure() async {
        let loader = FakeLoader()
        await loader.setDocumentError(FakeLoaderError.documentUnreadable)
        let model = DocumentViewerModel(documentID: UUID(), loader: loader, thumbnailLoader: FakeThumbnailLoader())

        model.load()
        await model.waitUntilIdle()

        #expect(model.state == .failure(.documentUnavailable))
    }

    @Test("retry after a document failure reloads")
    func retryAfterDocumentFailureReloads() async {
        let source = makeAssetReference()
        let page = makePage(index: 0, source: source)
        let document = makeDocument(pages: [page])

        let loader = FakeLoader()
        await loader.setDocumentError(FakeLoaderError.documentUnreadable)
        let model = DocumentViewerModel(documentID: document.id, loader: loader, thumbnailLoader: FakeThumbnailLoader())

        model.load()
        await model.waitUntilIdle()
        #expect(model.state == .failure(.documentUnavailable))

        await loader.clearDocumentError()
        await loader.setDocument(document)
        await loader.setAsset(Data("page".utf8), for: source)
        model.retry()
        await model.waitUntilIdle()

        guard case .content(let content) = model.state else {
            Issue.record("expected content state after retry")
            return
        }
        #expect(content.selectedPageID == page.id)
        #expect(await loader.documentCallCount == 2)
    }

    @Test("a page asset failure surfaces on the selected page and retry re-fetches it")
    func pageAssetFailureAndRetry() async {
        let source = makeAssetReference()
        let page = makePage(index: 0, source: source)
        let document = makeDocument(pages: [page])

        let loader = FakeLoader()
        await loader.setDocument(document)
        await loader.setAssetError(FakeLoaderError.assetUnreadable, for: source)

        let model = DocumentViewerModel(documentID: document.id, loader: loader, thumbnailLoader: FakeThumbnailLoader())
        model.load()
        await model.waitUntilIdle()

        guard case .content(let failed) = model.state else {
            Issue.record("expected content state")
            return
        }
        #expect(failed.pageAsset == .failure(.pageAssetUnavailable))

        await loader.clearAssetError(for: source)
        await loader.setAsset(Data("recovered".utf8), for: source)
        model.retry()
        await model.waitUntilIdle()

        guard case .content(let recovered) = model.state else {
            Issue.record("expected content state after retry")
            return
        }
        #expect(recovered.pageAsset == .loaded(Data("recovered".utf8)))
        #expect(await loader.readAssetCallCount == 2)
    }

    @Test("selecting a new page before a slower prior selection's asset finishes never lets the stale result win")
    func selectionRaceProtection() async {
        let sourceSlow = makeAssetReference()
        let sourceFast = makeAssetReference()
        let pageSlow = makePage(index: 0, source: sourceSlow)
        let pageFast = makePage(index: 1, source: sourceFast)
        let document = makeDocument(pages: [pageSlow, pageFast])

        let loader = FakeLoader()
        await loader.setDocument(document)
        await loader.setAsset(Data("slow".utf8), for: sourceSlow)
        await loader.setAssetDelay(nanoseconds: 150_000_000, for: sourceSlow)
        await loader.setAsset(Data("fast".utf8), for: sourceFast)

        let model = DocumentViewerModel(documentID: document.id, loader: loader, thumbnailLoader: FakeThumbnailLoader())
        model.load()
        await model.waitUntilIdle()

        // The initial load already kicked off the slow page's asset fetch; jump
        // to the fast page before it resolves.
        model.select(pageID: pageFast.id)
        await model.waitUntilIdle()

        guard case .content(let content) = model.state else {
            Issue.record("expected content state")
            return
        }
        #expect(content.selectedPageID == pageFast.id)
        #expect(content.pageAsset == .loaded(Data("fast".utf8)))

        // Let the slow fetch finish; it must not overwrite the now-current selection.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard case .content(let settled) = model.state else {
            Issue.record("expected content state")
            return
        }
        #expect(settled.selectedPageID == pageFast.id)
        #expect(settled.pageAsset == .loaded(Data("fast".utf8)))
    }

    @Test("a corrupt or missing rectified asset falls back to the immutable source")
    func rectifiedFailureFallsBackToSource() async {
        let source = makeAssetReference()
        let rectified = makeAssetReference()
        let page = makePage(index: 0, source: source, rectified: rectified)
        let document = makeDocument(pages: [page])

        let loader = FakeLoader()
        await loader.setDocument(document)
        await loader.setAssetError(FakeLoaderError.assetUnreadable, for: rectified)
        await loader.setAsset(Data("source".utf8), for: source)

        let model = DocumentViewerModel(documentID: document.id, loader: loader, thumbnailLoader: FakeThumbnailLoader())
        model.load()
        await model.waitUntilIdle()

        guard case .content(let content) = model.state else {
            Issue.record("expected content state")
            return
        }
        #expect(content.pageAsset == .loaded(Data("source".utf8)))
        #expect(content.isPageAssetRectified == false)
    }

    @Test("loadIfNeeded does not reset an already-loaded document to its first page")
    func loadIfNeededPreservesSelectionAcrossRemount() async {
        let sourceFirst = makeAssetReference()
        let sourceSecond = makeAssetReference()
        let pageFirst = makePage(index: 0, source: sourceFirst)
        let pageSecond = makePage(index: 1, source: sourceSecond)
        let document = makeDocument(pages: [pageFirst, pageSecond])

        let loader = FakeLoader()
        await loader.setDocument(document)
        await loader.setAsset(Data("first".utf8), for: sourceFirst)
        await loader.setAsset(Data("second".utf8), for: sourceSecond)

        let model = DocumentViewerModel(documentID: document.id, loader: loader, thumbnailLoader: FakeThumbnailLoader())
        model.loadIfNeeded()
        await model.waitUntilIdle()

        model.select(pageID: pageSecond.id)
        await model.waitUntilIdle()

        // Simulates a view's `.task` re-running after a compact/regular reflow
        // destroys and recreates the viewer surface.
        model.loadIfNeeded()
        await model.waitUntilIdle()

        guard case .content(let content) = model.state else {
            Issue.record("expected content state")
            return
        }
        #expect(content.selectedPageID == pageSecond.id)
        #expect(content.pageAsset == .loaded(Data("second".utf8)))
        #expect(await loader.documentCallCount == 1)
    }

    @Test("cancelling before a load resolves leaves the prior state untouched")
    func cancellationLeavesStateUntouched() async {
        let source = makeAssetReference()
        let page = makePage(index: 0, source: source)
        let document = makeDocument(pages: [page])

        let loader = FakeLoader()
        await loader.setDocument(document)
        await loader.setDocumentDelay(nanoseconds: 200_000_000)

        let model = DocumentViewerModel(documentID: document.id, loader: loader, thumbnailLoader: FakeThumbnailLoader())
        model.load()
        #expect(model.state == .loading)

        model.cancel()
        await model.waitUntilIdle()

        #expect(model.state == .loading)
    }

    @Test("loading a rail thumbnail never changes the selected page's full-resolution asset")
    func loadingThumbnailDoesNotChangeFullPageAsset() async throws {
        let sourceFirst = makeAssetReference()
        let sourceSecond = makeAssetReference()
        let pageFirst = makePage(index: 0, source: sourceFirst)
        let pageSecond = makePage(index: 1, source: sourceSecond)
        let document = makeDocument(pages: [pageFirst, pageSecond])

        let loader = FakeLoader()
        await loader.setDocument(document)
        await loader.setAsset(Data("full-res-first".utf8), for: sourceFirst)

        let thumbnailLoader = FakeThumbnailLoader()
        await thumbnailLoader.setThumbnail(Data("thumb-second".utf8), for: pageSecond.id)

        let model = DocumentViewerModel(documentID: document.id, loader: loader, thumbnailLoader: thumbnailLoader)
        model.load()
        await model.waitUntilIdle()

        // Load a thumbnail for the page that is not currently selected.
        let thumbnail = try await model.loadThumbnailData(for: pageSecond)
        #expect(thumbnail == Data("thumb-second".utf8))

        guard case .content(let content) = model.state else {
            Issue.record("expected content state")
            return
        }
        #expect(content.selectedPageID == pageFirst.id)
        #expect(content.pageAsset == .loaded(Data("full-res-first".utf8)))
        #expect(await loader.readAssetCallCount == 1)
    }
}
