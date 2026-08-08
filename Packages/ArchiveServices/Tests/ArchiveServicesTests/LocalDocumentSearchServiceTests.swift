import Foundation
import Testing
import WatakeDomain
@testable import ArchiveServices

@Suite("Local document search")
struct LocalDocumentSearchServiceTests {
    @Test("matches folder names")
    func matchesFolderNames() async throws {
        let folder = folder(1, name: "Café Archive")
        let service = LocalDocumentSearchService(repository: SearchRepository(folders: [folder]))

        let results = try await service.search(DocumentSearchQuery(" cafe  archive "))

        #expect(results == [ArchiveSearchResult.folder(FolderSearchResult(
            id: folder.id, name: folder.name, colorHex: folder.colorHex
        ))])
    }

    @Test("matches document names, tag labels, and OCR text")
    func matchesAllDocumentSources() async throws {
        let archive = folder(1)
        let tag = WatakeDomain.Tag(id: id(20), label: "Tax return", colorHex: "#3B82F6")
        let nameDocument = document(2, folder: archive, name: "Annual statement")
        let tagDocument = document(3, folder: archive, name: "Scan", tagIDs: [tag.id])
        let ocrDocument = document(4, folder: archive, name: "Receipt", ocrText: "paid in full")
        let repository = SearchRepository(
            folders: [archive], documents: [nameDocument, tagDocument, ocrDocument], tags: [tag]
        )
        let service = LocalDocumentSearchService(repository: repository)

        let nameResults = try await service.search(DocumentSearchQuery("STATEMENT"))
        let tagResults = try await service.search(DocumentSearchQuery("tax return"))
        let ocrResults = try await service.search(DocumentSearchQuery("PAID\nIN full"))

        #expect(documents(in: nameResults) == [searchResult(for: nameDocument, categories: [.name])])
        #expect(documents(in: tagResults) == [searchResult(for: tagDocument, categories: [.tag])])
        #expect(documents(in: ocrResults) == [searchResult(for: ocrDocument, categories: [.ocr])])
    }

    @Test("excludes every trashed folder and document")
    func excludesTrashedItems() async throws {
        let active = folder(1, name: "Active")
        let trashedFolder = folder(2, name: "Needle folder", deletedAt: Date(timeIntervalSince1970: 1))
        let activeDocument = document(3, folder: active, name: "Needle active")
        let trashedDocument = document(4, folder: active, name: "Needle document", deletedAt: Date(timeIntervalSince1970: 1))
        let hiddenByFolder = document(5, folder: trashedFolder, name: "Needle hidden")
        let service = LocalDocumentSearchService(repository: SearchRepository(
            folders: [active, trashedFolder], documents: [activeDocument, trashedDocument, hiddenByFolder]
        ))

        let results = try await service.search(DocumentSearchQuery("needle"))

        #expect(documents(in: results) == [searchResult(for: activeDocument, categories: [.name])])
    }

    @Test("sorts each match level then normalized name and UUID")
    func sortContractIsDeterministic() async throws {
        let archive = folder(1)
        let tag = WatakeDomain.Tag(id: id(20), label: "needle", colorHex: "#3B82F6")
        let exact = document(50, folder: archive, name: "Needle")
        let prefix = document(40, folder: archive, name: "Needlework")
        let substring = document(30, folder: archive, name: "A needle file")
        let tagMatch = document(20, folder: archive, name: "Zebra", tagIDs: [tag.id])
        let ocrMatch = document(10, folder: archive, name: "Alpha", ocrText: "needle inside")
        let sameNameHigherID = document(9, folder: archive, name: "Needle")
        let service = LocalDocumentSearchService(repository: SearchRepository(
            folders: [archive],
            documents: [ocrMatch, sameNameHigherID, tagMatch, substring, prefix, exact],
            tags: [tag]
        ))

        let results = try await service.search(DocumentSearchQuery("needle"))

        #expect(results.map(\.id) == [sameNameHigherID.id, exact.id, prefix.id, substring.id, tagMatch.id, ocrMatch.id])
        #expect(documents(in: results) == [
            searchResult(for: sameNameHigherID, categories: [.name]),
            searchResult(for: exact, categories: [.name]),
            searchResult(for: prefix, categories: [.name]),
            searchResult(for: substring, categories: [.name]),
            searchResult(for: tagMatch, categories: [.tag]),
            searchResult(for: ocrMatch, categories: [.ocr])
        ])
    }

    @Test("sort tie breakers use normalized name then UUID")
    func sortTieBreakersAreStable() async throws {
        let archive = folder(1)
        let alphabeticallyFirst = document(90, folder: archive, name: "Needle alpha")
        let alphabeticallyLast = document(2, folder: archive, name: "Needle zebra")
        let sameNameHigherID = document(60, folder: archive, name: "Needle same")
        let sameNameLowerID = document(3, folder: archive, name: "needle same")
        let service = LocalDocumentSearchService(repository: SearchRepository(
            folders: [archive], documents: [sameNameHigherID, alphabeticallyLast, sameNameLowerID, alphabeticallyFirst]
        ))

        let results = try await service.search(DocumentSearchQuery("needle"))

        #expect(results.map(\.id) == [
            alphabeticallyFirst.id,
            sameNameLowerID.id,
            sameNameHigherID.id,
            alphabeticallyLast.id
        ])
    }

    @Test("document returns every matching category without matched text")
    func multipleMatchCategories() async throws {
        let archive = folder(1)
        let tag = WatakeDomain.Tag(id: id(20), label: "needle", colorHex: "#3B82F6")
        let document = document(2, folder: archive, name: "Needle", tagIDs: [tag.id], ocrText: "needle")
        let service = LocalDocumentSearchService(repository: SearchRepository(
            folders: [archive], documents: [document], tags: [tag]
        ))

        let results = try await service.search(DocumentSearchQuery("needle"))

        #expect(documents(in: results) == [searchResult(for: document, categories: [.name, .tag, .ocr])])
    }

    @Test("whitespace-only query returns no results")
    func whitespaceOnlyQueryIsEmpty() async throws {
        let archive = folder(1)
        let service = LocalDocumentSearchService(repository: SearchRepository(
            folders: [archive], documents: [document(2, folder: archive, name: "Anything")]
        ))

        #expect(try await service.search(DocumentSearchQuery(" \n\t ")).isEmpty)
    }

    private func documents(in results: [ArchiveSearchResult]) -> [DocumentSearchResult] {
        results.compactMap {
            guard case .document(let document) = $0 else { return nil }
            return document
        }
    }

    private func searchResult(
        for document: StoredDocument,
        categories: Set<DocumentSearchMatchCategory>
    ) -> DocumentSearchResult {
        DocumentSearchResult(id: document.id, folderID: document.folderId, name: document.name, matchCategories: categories)
    }

    private func id(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }

    private func folder(_ value: UInt8, name: String = "Archive", deletedAt: Date? = nil) -> Folder {
        Folder(id: id(value), name: name, colorHex: "#3B82F6", createdAt: .distantPast, deletedAt: deletedAt)
    }

    private func document(
        _ value: UInt8,
        folder: Folder,
        name: String,
        tagIDs: [UUID] = [],
        ocrText: String? = nil,
        deletedAt: Date? = nil
    ) -> StoredDocument {
        let asset = AssetReference(
            id: id(value &+ 100), relativePath: "documents/\(value)/source.jpg",
            sha256Hex: String(repeating: "a", count: 64), byteSize: 1, mediaType: "image/jpeg"
        )
        return StoredDocument(
            id: id(value), folderId: folder.id, name: name, createdAt: .distantPast, updatedAt: .distantPast,
            orderIndex: Int(value), pages: [DocumentPage(id: id(value &+ 120), index: 0, source: asset, ocrText: ocrText)],
            deletedAt: deletedAt, tagIds: tagIDs
        )
    }
}

private actor SearchRepository: DocumentRepository {
    private let folderValues: [UUID: Folder]
    private let documentValues: [UUID: StoredDocument]
    private let tagValues: [UUID: WatakeDomain.Tag]

    init(folders: [Folder], documents: [StoredDocument] = [], tags: [WatakeDomain.Tag] = []) {
        folderValues = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        documentValues = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        tagValues = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
    }

    func folder(id: UUID) async throws -> Folder? {
        folderValues[id]
    }

    func folders() async throws -> [Folder] {
        Array(folderValues.values)
    }

    func saveFolder(_: Folder) async throws {}
    func document(id: UUID) async throws -> StoredDocument? {
        documentValues[id]
    }

    func documents(in folderId: UUID) async throws -> [StoredDocument] {
        documentValues.values.filter { $0.folderId == folderId }
    }

    func saveDocument(_: StoredDocument) async throws {}
    func moveDocument(_: StoredDocument) async throws {}
    func deleteDocument(id _: UUID) async throws {}
    func tags() async throws -> [WatakeDomain.Tag] {
        Array(tagValues.values)
    }

    func saveTag(_: WatakeDomain.Tag) async throws {}
    func watermarkPresets() async throws -> [WatermarkPreset] {
        []
    }

    func saveWatermarkPreset(_: WatermarkPreset) async throws {}
}
