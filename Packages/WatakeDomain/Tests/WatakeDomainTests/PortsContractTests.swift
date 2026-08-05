import Foundation
import Testing
@testable import WatakeDomain

@Suite("Port contracts")
struct PortsContractTests {
    @Test("DocumentRepository conformance threads deleteDocument through")
    func deleteDocumentThreadsThrough() async throws {
        let repository = InMemoryDocumentRepository()
        let document = makeDocument()
        try await repository.saveDocument(document)

        try await repository.deleteDocument(id: document.id)

        let stored = try await repository.document(id: document.id)
        #expect(stored == nil)
    }

    @Test("DocumentAssetStore conformance threads save/read through")
    func assetStoreRoundTripsThrough() async throws {
        let store = InMemoryDocumentAssetStore()
        let reference = makeAssetReference()
        let bytes = Data("page-bytes".utf8)

        try await store.saveAsset(bytes, reference: reference)
        let exists = try await store.containsAsset(reference)
        let read = try await store.readAsset(reference)

        #expect(exists)
        #expect(read == bytes)
    }
}

private actor InMemoryDocumentRepository: DocumentRepository {
    private var documents: [UUID: StoredDocument] = [:]

    func folder(id: UUID) async throws -> Folder? {
        nil
    }

    func folders() async throws -> [Folder] {
        []
    }

    func saveFolder(_ folder: Folder) async throws {}

    func document(id: UUID) async throws -> StoredDocument? {
        documents[id]
    }

    func documents(in folderId: UUID) async throws -> [StoredDocument] {
        documents.values.filter { $0.folderId == folderId }
    }

    func saveDocument(_ document: StoredDocument) async throws {
        documents[document.id] = document
    }

    func moveDocument(_ document: StoredDocument) async throws {
        documents[document.id] = document
    }

    func deleteDocument(id: UUID) async throws {
        documents.removeValue(forKey: id)
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

private actor InMemoryDocumentAssetStore: DocumentAssetStore {
    private var assets: [UUID: Data] = [:]

    func saveAsset(_ data: Data, reference: AssetReference) async throws {
        assets[reference.id] = data
    }

    func readAsset(_ reference: AssetReference) async throws -> Data {
        assets[reference.id] ?? Data()
    }

    func containsAsset(_ reference: AssetReference) async throws -> Bool {
        assets[reference.id] != nil
    }

    func removeAsset(_ reference: AssetReference) async throws {
        assets.removeValue(forKey: reference.id)
    }
}

private func fixedUUID(_ value: Int) -> UUID {
    let byte = UInt8(value)
    return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
}

private func makeAssetReference() -> AssetReference {
    let path = [
        "folders/00000000-0000-0000-0000-000000000001",
        "documents/00000000-0000-0000-0000-000000000002",
        "pages/00000000-0000-0000-0000-000000000003",
        "source.jpg"
    ].joined(separator: "/")
    return AssetReference(
        id: fixedUUID(10),
        relativePath: path,
        sha256Hex: String(repeating: "a", count: 64),
        byteSize: 10,
        mediaType: "image/jpeg"
    )
}

private func makePage() -> DocumentPage {
    DocumentPage(
        id: fixedUUID(3),
        index: 0,
        source: makeAssetReference()
    )
}

private func makeDocument() -> StoredDocument {
    StoredDocument(
        id: fixedUUID(2),
        folderId: fixedUUID(1),
        name: "Document",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        orderIndex: 0,
        pages: [makePage()]
    )
}
