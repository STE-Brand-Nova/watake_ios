import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

@Suite("OCR persistence")
struct OCRPersistenceTests {
    @Test("encrypted OCR page data reloads through a new storage adapter")
    func OCRDataReloads() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }

        let folder = makeFolder()
        let documentID = UUID()
        let data = Data("synthetic-page".utf8)
        let asset = makeAssetReference(folderId: folder.id, documentId: documentID, bytes: data)
        let pageID = UUID()
        let original = StoredDocument(
            id: documentID,
            folderId: folder.id,
            name: "Synthetic document",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            orderIndex: 0,
            pages: [DocumentPage(id: pageID, index: 0, source: asset)]
        )
        let writer = makeStorage(root: root, service: service)
        try await writer.saveFolder(folder)
        try await writer.saveAsset(data, reference: asset)
        try await writer.saveDocument(original)

        let recognized = OCRBlock(
            id: UUID(),
            text: "synthetic text",
            confidence: 0.8,
            bounds: NormalizedRect(originX: 0.1, originY: 0.2, width: 0.3, height: 0.1),
            language: "en"
        )
        let updated = StoredDocument(
            id: original.id,
            folderId: original.folderId,
            name: original.name,
            createdAt: original.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            orderIndex: original.orderIndex,
            pages: [DocumentPage(id: pageID, index: 0, source: asset, ocrText: "synthetic text", ocrBlocks: [recognized])]
        )
        try await writer.saveDocument(updated)

        let reader = makeStorage(root: root, service: service)
        let reloaded = try #require(await reader.document(id: documentID))
        let page = try #require(reloaded.pages.first)
        #expect(page.ocrText == "synthetic text")
        #expect(page.ocrBlocks == [recognized])
    }
}
