import Foundation
import Observation
import WatakeDomain

public enum DocumentSearchState: Equatable, Sendable {
    case emptyQuery
    case loading
    case results([ArchiveSearchResult])
    case noResults
    case failure
}

/// Owns debouncing and supersession for a search surface. The model exposes no
/// persistence details or private matched text. `open(_:)` validates a row
/// against the latest result snapshot; routing remains the app's concern.
@MainActor
@Observable
public final class DocumentSearchModel {
    public private(set) var query = ""
    public private(set) var state: DocumentSearchState = .emptyQuery

    private let searcher: any DocumentSearching
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?
    private var generation = 0

    public init(searcher: any DocumentSearching, debounce: Duration = .milliseconds(250)) {
        self.searcher = searcher
        self.debounce = debounce
    }

    public func updateQuery(_ value: String) {
        query = value
        generation &+= 1
        let requestGeneration = generation
        searchTask?.cancel()

        let normalizedQuery = DocumentSearchQuery(value)
        guard !normalizedQuery.isEmpty else {
            state = .emptyQuery
            searchTask = nil
            return
        }

        state = .loading
        searchTask = Task { [weak self, normalizedQuery] in
            await self?.performSearch(query: normalizedQuery, generation: requestGeneration)
        }
    }

    public func retry() {
        updateQuery(query)
    }

    /// Clears the visible query and every rendered search state when the
    /// search destination is dismissed. Incrementing the generation keeps a
    /// non-cooperative in-flight search from publishing after dismissal.
    public func reset() {
        generation &+= 1
        searchTask?.cancel()
        searchTask = nil
        query = ""
        state = .emptyQuery
    }

    /// Returns a result only when it still belongs to the latest rendered
    /// snapshot. The app can then route folder/document IDs without views
    /// retaining or re-querying private archive records.
    public func open(_ result: ArchiveSearchResult) -> ArchiveSearchResult? {
        guard case .results(let results) = state, results.contains(result) else { return nil }
        return result
    }

    func waitUntilIdle() async {
        await searchTask?.value
    }

    private func performSearch(query: DocumentSearchQuery, generation: Int) async {
        do {
            try await Task.sleep(for: debounce)
            try Task.checkCancellation()
            let results = try await searcher.search(query)
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            state = results.isEmpty ? .noResults : .results(results)
        } catch is CancellationError {
            // Superseded input leaves the newer request's state untouched.
        } catch {
            guard !Task.isCancelled, generation == self.generation else { return }
            state = .failure
        }
    }
}
