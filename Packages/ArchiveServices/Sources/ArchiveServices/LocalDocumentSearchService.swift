import Foundation
import WatakeDomain

/// Searches active archive metadata through the repository boundary. Sorting
/// is deterministic and independent of filesystem enumeration order:
/// exact name, name prefix, name substring, tag, OCR, normalized display name,
/// then UUID. OCR/tag strings never leave this service.
public actor LocalDocumentSearchService: DocumentSearching {
    private let repository: any DocumentRepository

    public init(repository: any DocumentRepository) {
        self.repository = repository
    }

    public func search(_ query: DocumentSearchQuery) async throws -> [ArchiveSearchResult] {
        guard !query.isEmpty else { return [] }

        let tagsByID = try await Dictionary(uniqueKeysWithValues: repository.tags().map { ($0.id, $0) })
        let activeFolders = try await repository.folders().filter { $0.deletedAt == nil }
        var results: [ArchiveSearchResult] = []

        for folder in activeFolders {
            try Task.checkCancellation()
            if query.matches(folder.name) {
                results.append(.folder(FolderSearchResult(id: folder.id, name: folder.name, colorHex: folder.colorHex)))
            }

            let documents = try await repository.documents(in: folder.id)
            for document in documents where document.deletedAt == nil {
                try Task.checkCancellation()
                var categories = Set<DocumentSearchMatchCategory>()
                if query.matches(document.name) {
                    categories.insert(.name)
                }
                if document.tagIds.contains(where: { tagsByID[$0].map { query.matches($0.label) } ?? false }) {
                    categories.insert(.tag)
                }
                if document.pages.contains(where: { page in
                    page.ocrText.map(query.matches) ?? false
                }) {
                    categories.insert(.ocr)
                }
                if !categories.isEmpty {
                    results.append(.document(DocumentSearchResult(
                        id: document.id,
                        folderID: folder.id,
                        name: document.name,
                        matchCategories: categories
                    )))
                }
            }
        }
        return results.sorted { left, right in
            SearchSortContract.comesBefore(left, right, query: query)
        }
    }
}

enum SearchSortContract {
    static func comesBefore(_ left: ArchiveSearchResult, _ right: ArchiveSearchResult, query: DocumentSearchQuery) -> Bool {
        let leftRank = rank(of: left, query: query)
        let rightRank = rank(of: right, query: query)
        if leftRank != rightRank {
            return leftRank < rightRank
        }

        // Fixed normalization and Swift's Unicode scalar comparison avoid
        // locale-dependent ordering. UUID makes otherwise equal names stable.
        let leftName = DocumentSearchText.normalize(left.displayName)
        let rightName = DocumentSearchText.normalize(right.displayName)
        if leftName != rightName {
            return leftName < rightName
        }
        return left.id.uuidString.lowercased() < right.id.uuidString.lowercased()
    }

    private static func rank(of result: ArchiveSearchResult, query: DocumentSearchQuery) -> Int {
        let name = DocumentSearchText.normalize(result.displayName)
        if name == query.normalizedValue {
            return 0
        }
        if name.hasPrefix(query.normalizedValue) {
            return 1
        }
        if name.contains(query.normalizedValue) {
            return 2
        }
        guard case .document(let document) = result else { return 5 }
        if document.matchCategories.contains(.tag) {
            return 3
        }
        if document.matchCategories.contains(.ocr) {
            return 4
        }
        return 5
    }
}
