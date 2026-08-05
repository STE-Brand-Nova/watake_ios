import Foundation
import Testing
import WatakeDomain
@testable import CaptureServices

struct ImportedDocumentServiceTests {
    @Test func groupingMakesOrderedMultiPageOrSeparateDocuments() async throws {
        let folder = Folder(id: UUID(), name: "Inbox", colorHex: "#3B82F6", createdAt: .now)
        let repository = ImportRepository(folder: folder)
        let assets = ImportAssets()
        let service = ImportedDocumentService(repository: repository, assetStore: assets, serialiser: FolderScanOperationSerialiser())
        let pages = [ImportedPage(sourceData: Data([1])), ImportedPage(sourceData: Data([2]))]

        let grouped = try await service.save(pages: pages, grouping: .oneDocument, into: folder.id, named: "Receipt")
        #expect(grouped.count == 1)
        #expect(grouped[0].pages.map(\.index) == [0, 1])
        let separated = try await service.save(pages: pages, grouping: .separateDocuments, into: folder.id, named: "Receipt")
        #expect(separated.count == 2)
        #expect(separated.allSatisfy { $0.pages.count == 1 })
    }

    @Test func failedAssetWriteCleansUpEarlierAssets() async {
        let folder = Folder(id: UUID(), name: "Inbox", colorHex: "#3B82F6", createdAt: .now)
        let assets = ImportAssets(failOn: 2)
        let service = ImportedDocumentService(
            repository: ImportRepository(folder: folder), assetStore: assets, serialiser: FolderScanOperationSerialiser()
        )
        await #expect(throws: ImportTestError.failed) {
            try await service.save(
                pages: [ImportedPage(sourceData: Data([1])), ImportedPage(sourceData: Data([2]))],
                into: folder.id, named: "Receipt"
            )
        }
        #expect(await assets.savedCount == 0)
    }

    @Test func nonJPEGSourceKeepsMediaTypeAndExtension() throws {
        let page = ImportedPage(sourceData: Data([1, 2]), sourceMediaType: "image/heic", sourceFileExtension: "heic")
        let document = try ImportedDocumentFactory().makeDocument(folderID: UUID(), name: "Photo", orderIndex: 0, pages: [page])

        #expect(document.pages[0].source.mediaType == "image/heic")
        #expect(document.pages[0].source.relativePath.hasSuffix("source.heic"))
    }

    @Test func separateImportFailureRollsBackEarlierDocuments() async {
        let folder = Folder(id: UUID(), name: "Inbox", colorHex: "#3B82F6", createdAt: .now)
        let repository = ImportRepository(folder: folder)
        let assets = ImportAssets(failOn: 2)
        let service = ImportedDocumentService(repository: repository, assetStore: assets, serialiser: FolderScanOperationSerialiser())

        await #expect(throws: ImportTestError.failed) {
            try await service.save(
                pages: [ImportedPage(sourceData: Data([1])), ImportedPage(sourceData: Data([2]))],
                grouping: .separateDocuments,
                into: folder.id,
                named: "Receipt"
            )
        }
        #expect(await repository.documentCount == 0)
    }
}

private enum ImportTestError: Error, Sendable { case failed }

private actor ImportRepository: DocumentRepository {
    let storedFolder: Folder
    private var values: [StoredDocument] = []
    init(folder: Folder) {
        storedFolder = folder
    }

    func folder(id: UUID) async throws -> Folder? {
        storedFolder.id == id ? storedFolder : nil
    }

    func folders() async throws -> [Folder] {
        [storedFolder]
    }

    func saveFolder(_ folder: Folder) async throws {}
    func document(id: UUID) async throws -> StoredDocument? {
        values.first { $0.id == id }
    }

    func documents(in folderId: UUID) async throws -> [StoredDocument] {
        values
    }

    func saveDocument(_ document: StoredDocument) async throws {
        values.removeAll { $0.id == document.id }
        values.append(document)
    }

    func moveDocument(_ document: StoredDocument) async throws {
        values.removeAll { $0.id == document.id }
        values.append(document)
    }

    func deleteDocument(id: UUID) async throws {
        values.removeAll { $0.id == id }
    }

    var documentCount: Int {
        values.count
    }

    func tags() async throws -> [WatakeDomain.Tag] {
        []
    }

    func saveTag(_ tag: WatakeDomain.Tag) async throws {}
    func watermarkPresets() async throws -> [WatermarkPreset] {
        []
    }

    func saveWatermarkPreset(_ preset: WatermarkPreset) async throws {}
}

private actor ImportAssets: DocumentAssetStore {
    private var values: Set<UUID> = []
    private var attempts = 0
    private let failOn: Int?
    init(failOn: Int? = nil) {
        self.failOn = failOn
    }

    var savedCount: Int {
        values.count
    }

    func saveAsset(_ data: Data, reference: AssetReference) async throws {
        attempts += 1
        if attempts == failOn {
            throw ImportTestError.failed
        }
        values.insert(reference.id)
    }

    func readAsset(_ reference: AssetReference) async throws -> Data {
        Data()
    }

    func containsAsset(_ reference: AssetReference) async throws -> Bool {
        values.contains(reference.id)
    }

    func removeAsset(_ reference: AssetReference) async throws {
        values.remove(reference.id)
    }
}
