import Foundation
import WatakeDomain

enum FakeLoaderError: Error, Equatable {
    case documentUnreadable
    case assetUnreadable
    case missingFixture
}

/// In-memory `DocumentPageAssetLoading` double. No WatakeStorage dependency:
/// `DocumentViewerFeature` must never link it, so tests exercise the model
/// against this fake instead.
actor FakeLoader: DocumentPageAssetLoading {
    private var documentsByID: [UUID: StoredDocument] = [:]
    private var documentError: Error?
    private var documentDelayNanoseconds: UInt64?
    private(set) var documentCallCount = 0

    private var assetData: [UUID: Data] = [:]
    private var assetErrors: [UUID: Error] = [:]
    private var assetDelayNanosecondsByReference: [UUID: UInt64] = [:]
    private(set) var readAssetCallCount = 0

    func document(id: UUID) async throws -> StoredDocument? {
        documentCallCount += 1
        if let documentDelayNanoseconds {
            try await Task.sleep(nanoseconds: documentDelayNanoseconds)
        }
        if let documentError {
            throw documentError
        }
        return documentsByID[id]
    }

    func readAsset(_ reference: AssetReference) async throws -> Data {
        readAssetCallCount += 1
        if let delay = assetDelayNanosecondsByReference[reference.id] {
            try await Task.sleep(nanoseconds: delay)
        }
        if let error = assetErrors[reference.id] {
            throw error
        }
        guard let data = assetData[reference.id] else {
            throw FakeLoaderError.missingFixture
        }
        return data
    }

    func setDocument(_ document: StoredDocument) {
        documentsByID[document.id] = document
    }

    func setDocumentError(_ error: Error) {
        documentError = error
    }

    func clearDocumentError() {
        documentError = nil
    }

    func setDocumentDelay(nanoseconds: UInt64) {
        documentDelayNanoseconds = nanoseconds
    }

    func setAsset(_ data: Data, for reference: AssetReference) {
        assetData[reference.id] = data
    }

    func setAssetError(_ error: Error, for reference: AssetReference) {
        assetErrors[reference.id] = error
    }

    func clearAssetError(for reference: AssetReference) {
        assetErrors[reference.id] = nil
    }

    func setAssetDelay(nanoseconds: UInt64, for reference: AssetReference) {
        assetDelayNanosecondsByReference[reference.id] = nanoseconds
    }
}

func makeAssetReference(id: UUID = UUID(), path: String = "page.bin") -> AssetReference {
    AssetReference(
        id: id,
        relativePath: path,
        sha256Hex: String(repeating: "0", count: 64),
        byteSize: 1,
        mediaType: "application/octet-stream"
    )
}

func makePage(id: UUID = UUID(), index: Int, source: AssetReference, rectified: AssetReference? = nil) -> DocumentPage {
    DocumentPage(id: id, index: index, source: source, rectified: rectified)
}

func makeDocument(id: UUID = UUID(), folderId: UUID = UUID(), name: String = "Diploma", pages: [DocumentPage]) -> StoredDocument {
    StoredDocument(
        id: id,
        folderId: folderId,
        name: name,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        orderIndex: 0,
        pages: pages
    )
}
