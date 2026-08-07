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

/// In-memory `DocumentPageThumbnailLoading` double, independent of the
/// full-page `FakeLoader` so tests can assert the two paths never interfere.
actor FakeThumbnailLoader: DocumentPageThumbnailLoading {
    private var thumbnailsByPageID: [UUID: Data] = [:]
    private var errorsByPageID: [UUID: Error] = [:]
    private(set) var thumbnailCallCount = 0

    func thumbnail(for page: DocumentPage) async throws -> Data {
        thumbnailCallCount += 1
        if let error = errorsByPageID[page.id] {
            throw error
        }
        guard let data = thumbnailsByPageID[page.id] else {
            throw FakeLoaderError.missingFixture
        }
        return data
    }

    func setThumbnail(_ data: Data, for pageID: UUID) {
        thumbnailsByPageID[pageID] = data
    }

    func setError(_ error: Error, for pageID: UUID) {
        errorsByPageID[pageID] = error
    }
}

actor FakeOCRStore: DocumentOCRPersisting, DocumentPageAssetLoading {
    private var storedDocument: StoredDocument?
    private var assets: [UUID: Data] = [:]
    private(set) var saveCount = 0
    private var suspendsSave = false
    private var didStartSave = false
    private var saveStartedContinuation: CheckedContinuation<Void, Never>?
    private var saveCompletionContinuation: CheckedContinuation<Void, Never>?

    func document(id: UUID) async throws -> StoredDocument? {
        storedDocument?.id == id ? storedDocument : nil
    }

    func readAsset(_ reference: AssetReference) async throws -> Data {
        guard let data = assets[reference.id] else { throw FakeLoaderError.missingFixture }
        return data
    }

    func saveDocument(_ document: StoredDocument) async throws {
        if suspendsSave {
            didStartSave = true
            saveStartedContinuation?.resume()
            saveStartedContinuation = nil
            await withCheckedContinuation { saveCompletionContinuation = $0 }
        }
        storedDocument = document
        saveCount += 1
    }

    func seed(document: StoredDocument, assets: [UUID: Data]) {
        storedDocument = document
        self.assets = assets
    }

    func suspendNextSave() {
        suspendsSave = true
    }

    var saveStarted: Void {
        get async {
            guard !didStartSave else { return }
            await withCheckedContinuation { saveStartedContinuation = $0 }
        }
    }

    func finishSave() {
        suspendsSave = false
        saveCompletionContinuation?.resume()
        saveCompletionContinuation = nil
    }
}

actor FakeOCRRecognizer: OCRRecognizing {
    private var results: [OCRRecognitionResult] = []
    private var failure = false
    private var delayNanoseconds: UInt64?

    func recognize(imageData _: Data, configuration _: OCRConfiguration) async throws -> OCRRecognitionResult {
        if let delayNanoseconds {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if failure {
            throw OCRRecognitionError.requestFailed
        }
        guard !results.isEmpty else { return OCRRecognitionResult(text: "", blocks: []) }
        return results.removeFirst()
    }

    func setResults(_ results: [OCRRecognitionResult]) {
        self.results = results
    }

    func setFailure(_ failure: Bool) {
        self.failure = failure
    }

    func setDelay(nanoseconds: UInt64) {
        delayNanoseconds = nanoseconds
    }
}

actor NonCooperativeOCRRecognizer: OCRRecognizing {
    private var result: OCRRecognitionResult?
    private var didStart = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var completionContinuation: CheckedContinuation<Void, Never>?

    func recognize(imageData _: Data, configuration _: OCRConfiguration) async throws -> OCRRecognitionResult {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { completionContinuation = $0 }
        return result ?? OCRRecognitionResult(text: "", blocks: [])
    }

    var started: Void {
        get async {
            guard !didStart else { return }
            await withCheckedContinuation { startedContinuation = $0 }
        }
    }

    func finish(with result: OCRRecognitionResult) {
        self.result = result
        completionContinuation?.resume()
        completionContinuation = nil
    }
}

@MainActor
final class OCRPersistenceRecorder: @unchecked Sendable {
    private(set) var documents: [StoredDocument] = []

    func record(_ document: StoredDocument) {
        documents.append(document)
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
