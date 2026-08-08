import Foundation

/// Normalized, privacy-safe search input. Empty means the user entered only
/// whitespace, so callers must show guidance rather than query storage.
public struct DocumentSearchQuery: Equatable, Hashable, Sendable {
    public let normalizedValue: String

    public init(_ value: String) {
        normalizedValue = DocumentSearchText.normalize(value)
    }

    public var isEmpty: Bool {
        normalizedValue.isEmpty
    }

    public func matches(_ value: String) -> Bool {
        !isEmpty && DocumentSearchText.normalize(value).contains(normalizedValue)
    }
}

/// Shared normalization for names, labels, and private OCR text. Folding uses
/// a fixed locale so both matching and deterministic sort keys do not vary
/// with the device's language or region settings.
public enum DocumentSearchText {
    private static let locale = Locale(identifier: "en_US_POSIX")

    public static func normalize(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// Why a document appears in a search result. OCR text and tag labels remain
/// private; result values expose only these categories, never a matched snippet.
public enum DocumentSearchMatchCategory: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case name
    case tag
    case ocr
}

/// Folder result carries only metadata necessary to navigate to its archive.
public struct FolderSearchResult: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let colorHex: String

    public init(id: UUID, name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

/// Document result carries only navigation metadata and match categories. It
/// deliberately stores no OCR or tag text copy for search presentation.
public struct DocumentSearchResult: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let folderID: UUID
    public let name: String
    public let matchCategories: Set<DocumentSearchMatchCategory>

    public init(id: UUID, folderID: UUID, name: String, matchCategories: Set<DocumentSearchMatchCategory>) {
        self.id = id
        self.folderID = folderID
        self.name = name
        self.matchCategories = matchCategories
    }
}

/// Stable value result for local archive search.
public enum ArchiveSearchResult: Identifiable, Equatable, Sendable {
    case folder(FolderSearchResult)
    case document(DocumentSearchResult)

    public var id: UUID {
        switch self {
        case .folder(let result): result.id
        case .document(let result): result.id
        }
    }

    public var displayName: String {
        switch self {
        case .folder(let result): result.name
        case .document(let result): result.name
        }
    }
}
