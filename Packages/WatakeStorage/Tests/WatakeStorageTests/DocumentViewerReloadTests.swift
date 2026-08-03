import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

/// Proves the storage evidence `DocumentViewerFeature` relies on: a saved
/// multi-page document, and its ordered page assets, survive recreating the
/// storage adapter (i.e. an app relaunch reading the same on-disk root).
@Suite("Document viewer reload after storage adapter recreation")
struct DocumentViewerReloadTests {
    @Test("a saved multi-page document reloads in page order through a new adapter instance")
    func multiPageDocumentReloadsInOrder() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }

        let folder = makeFolder()
        let documentID = UUID()

        let bytesPage0 = Data("page-0".utf8)
        let bytesPage1Source = Data("page-1-source".utf8)
        let bytesPage1Rectified = Data("page-1-rectified".utf8)

        let sourcePage0 = makeAssetReference(folderId: folder.id, documentId: documentID, bytes: bytesPage0)
        let sourcePage1 = makeAssetReference(folderId: folder.id, documentId: documentID, bytes: bytesPage1Source)
        let rectifiedPage1 = makeAssetReference(folderId: folder.id, documentId: documentID, kind: "rectified", bytes: bytesPage1Rectified)

        do {
            // Writer: saves the folder, document, and every page asset, then
            // goes out of scope so nothing but the disk root survives.
            let writer = makeStorage(root: root, service: service)
            try await writer.saveFolder(folder)
            try await writer.saveAsset(bytesPage0, reference: sourcePage0)
            try await writer.saveAsset(bytesPage1Source, reference: sourcePage1)
            try await writer.saveAsset(bytesPage1Rectified, reference: rectifiedPage1)

            let document = StoredDocument(
                id: documentID,
                folderId: folder.id,
                name: "Multi-page scan",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                orderIndex: 0,
                pages: [
                    DocumentPage(id: UUID(), index: 1, source: sourcePage1, rectified: rectifiedPage1),
                    DocumentPage(id: UUID(), index: 0, source: sourcePage0)
                ]
            )
            try await writer.saveDocument(document)
        }

        // Reader: a freshly constructed adapter over the same root, standing
        // in for a relaunched app reopening the document from its folder.
        let reader = makeStorage(root: root, service: service)

        let reloaded = try await reader.document(id: documentID)
        let pages = try #require(reloaded?.pages.sorted { $0.index < $1.index })
        #expect(pages.map(\.index) == [0, 1])

        let firstPageData = try await reader.readAsset(pages[0].source)
        #expect(firstPageData == bytesPage0)

        let secondPageSourceData = try await reader.readAsset(pages[1].source)
        #expect(secondPageSourceData == bytesPage1Source)

        let secondPageRectifiedData = try await reader.readAsset(#require(pages[1].rectified))
        #expect(secondPageRectifiedData == bytesPage1Rectified)

        let documentsInFolder = try await reader.documents(in: folder.id)
        #expect(documentsInFolder.map(\.id) == [documentID])
    }
}
