import Foundation
import Testing
import WatakeDomain
@testable import DocumentSearchFeature

@MainActor
@Suite("Document search model")
struct DocumentSearchModelTests {
    @Test("empty query shows guidance without calling search")
    func emptyQueryShowsGuidance() async {
        let searcher = SearcherDouble()
        let model = DocumentSearchModel(searcher: searcher, debounce: .milliseconds(0))

        model.updateQuery(" \n\t ")

        #expect(model.state == .emptyQuery)
        #expect(await searcher.callCount == 0)
    }

    @Test("debounces input before calling search")
    func debounceDelaysSearch() async {
        let searcher = SearcherDouble(responses: [.success([folderResult(1, name: "Archive")])])
        let model = DocumentSearchModel(searcher: searcher, debounce: .milliseconds(50))

        model.updateQuery("archive")

        #expect(model.state == .loading)
        #expect(await searcher.callCount == 0)
        await model.waitUntilIdle()
        #expect(await searcher.callCount == 1)
    }

    @Test("publishes results and opens only a current result")
    func resultsAndOpening() async {
        let result = folderResult(1, name: "Archive")
        let searcher = SearcherDouble(responses: [.success([result])])
        let model = DocumentSearchModel(searcher: searcher, debounce: .milliseconds(0))

        model.updateQuery("archive")
        #expect(model.state == .loading)
        await model.waitUntilIdle()

        #expect(model.state == .results([result]))
        #expect(model.open(result) == result)
        #expect(model.open(folderResult(2, name: "Other")) == nil)
    }

    @Test("no results and failure retry publish safe states")
    func noResultsAndFailureRetry() async {
        let searcher = SearcherDouble(responses: [
            .success([]),
            .failure(SearcherError.unavailable),
            .success([folderResult(1, name: "Archive")])
        ])
        let model = DocumentSearchModel(searcher: searcher, debounce: .milliseconds(0))

        model.updateQuery("missing")
        await model.waitUntilIdle()
        #expect(model.state == .noResults)

        model.updateQuery("archive")
        await model.waitUntilIdle()
        #expect(model.state == .failure)

        model.retry()
        await model.waitUntilIdle()
        #expect(model.state == .results([folderResult(1, name: "Archive")]))
    }

    @Test("non-cooperative stale search cannot replace newer results")
    func staleResultsCannotWin() async {
        let oldResult = folderResult(1, name: "Old")
        let newResult = folderResult(2, name: "New")
        let searcher = NonCooperativeSearcher()
        let model = DocumentSearchModel(searcher: searcher, debounce: .milliseconds(0))

        model.updateQuery("old")
        await searcher.waitForCallCount(1)
        model.updateQuery("new")
        await searcher.waitForCallCount(2)
        await searcher.finishNext(with: [oldResult])
        await searcher.finishNext(with: [newResult])
        await model.waitUntilIdle()

        #expect(model.state == .results([newResult]))
    }

    @Test("reset clears visible query and ignores a late cancelled result")
    func resetClearsStateAndPreventsLateResult() async {
        let staleResult = folderResult(1, name: "Stale")
        let searcher = NonCooperativeSearcher()
        let model = DocumentSearchModel(searcher: searcher, debounce: .milliseconds(0))

        model.updateQuery("stale")
        await searcher.waitForCallCount(1)
        model.reset()
        await searcher.finishNext(with: [staleResult])
        await Task.yield()

        #expect(model.query.isEmpty)
        #expect(model.state == .emptyQuery)
    }

    private func folderResult(_ value: UInt8, name: String) -> ArchiveSearchResult {
        .folder(FolderSearchResult(id: id(value), name: name, colorHex: "#3B82F6"))
    }

    private func id(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}

private enum SearcherError: Error, Sendable {
    case unavailable
}

private actor SearcherDouble: DocumentSearching {
    private var responses: [Result<[ArchiveSearchResult], Error>]
    private(set) var callCount = 0

    init(responses: [Result<[ArchiveSearchResult], Error>] = []) {
        self.responses = responses
    }

    func search(_: DocumentSearchQuery) async throws -> [ArchiveSearchResult] {
        callCount += 1
        guard !responses.isEmpty else { return [] }
        return try responses.removeFirst().get()
    }
}

private actor NonCooperativeSearcher: DocumentSearching {
    private var continuations: [CheckedContinuation<[ArchiveSearchResult], Never>] = []
    private var callCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func search(_: DocumentSearchQuery) async throws -> [ArchiveSearchResult] {
        callCount += 1
        resumeSatisfiedWaiters()
        return await withCheckedContinuation { continuations.append($0) }
    }

    func waitForCallCount(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { waiters.append($0) }
        await waitForCallCount(count)
    }

    func finishNext(with results: [ArchiveSearchResult]) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: results)
    }

    private func resumeSatisfiedWaiters() {
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume() }
    }
}
