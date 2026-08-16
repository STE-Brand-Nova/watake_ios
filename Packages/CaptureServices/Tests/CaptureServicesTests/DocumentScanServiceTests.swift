import Foundation
import Testing
import WatakeDomain
@testable import CaptureServices

struct DocumentScanServiceTests {
    @Test func createsOrderedPagesWithVerifiedAssetReferences() throws {
        let factory = ScannedDocumentFactory(
            now: { Date(timeIntervalSince1970: 1000) }
        )

        let document = try factory.makeDocument(
            folderID: UUID(),
            name: "Receipt",
            orderIndex: 2,
            pages: [ScannedPage(jpegData: Data([1, 2])), ScannedPage(jpegData: Data([3]))]
        )

        #expect(document.pages.map(\.index) == [0, 1])
        #expect(document.pages[0].source
            .relativePath ==
            "documents/\(document.id.uuidString.lowercased())/source/\(document.pages[0].source.id.uuidString.lowercased()).jpg")
        #expect(document.pages[1].source
            .relativePath ==
            "documents/\(document.id.uuidString.lowercased())/source/\(document.pages[1].source.id.uuidString.lowercased()).jpg")
        #expect(document.pages[0].source.byteSize == 2)
        #expect(document.pages[0].source.sha256Hex == "a12871fee210fb8619291eaea194581cbd2531e4b23759d225f6806923f63222")
        #expect(document.pages.allSatisfy { $0.source.mediaType == "image/jpeg" })
    }

    @Test func rejectsEmptyScan() {
        let factory = ScannedDocumentFactory()

        #expect(throws: DocumentScanSaveError.emptyScan) {
            try factory.makeDocument(folderID: UUID(), name: "Empty", orderIndex: 0, pages: [])
        }
    }

    @Test func rejectsMissingAndTrashedFoldersBeforeCapture() async {
        let missingRepository = FakeRepository(folder: nil)
        let pageCapturer = FakePageCapturer(result: .success([ScannedPage(jpegData: Data([1]))]))
        let service = DocumentScanService(
            pageCapturer: pageCapturer,
            repository: missingRepository,
            assetStore: FakeAssetStore(),
            operationSerialiser: FolderScanOperationSerialiser()
        )

        await #expect(throws: DocumentScanSaveError.targetFolderMissing) {
            try await service.scanDocument(into: UUID(), named: "Scan")
        }
        #expect(await pageCapturer.captureCount == 0)

        let trashedFolder = makeFolder(deletedAt: Date())
        let trashedRepository = FakeRepository(folder: trashedFolder)
        let trashedService = DocumentScanService(
            pageCapturer: pageCapturer,
            repository: trashedRepository,
            assetStore: FakeAssetStore(),
            operationSerialiser: FolderScanOperationSerialiser()
        )
        await #expect(throws: DocumentScanSaveError.targetFolderTrashed) {
            try await trashedService.scanDocument(into: trashedFolder.id, named: "Scan")
        }
    }

    @Test func removesOnlyStagedAssetsWhenMetadataSaveFails() async throws {
        let folder = makeFolder()
        let repository = FakeRepository(folder: folder, saveDocumentError: TestError.failed)
        let assets = FakeAssetStore()
        let service = DocumentScanService(
            pageCapturer: FakePageCapturer(result: .success([ScannedPage(jpegData: Data([1])), ScannedPage(jpegData: Data([2]))])),
            repository: repository,
            assetStore: assets,
            operationSerialiser: FolderScanOperationSerialiser()
        )

        await #expect(throws: TestError.failed) {
            try await service.scanDocument(into: folder.id, named: "Scan")
        }
        let saved = await assets.saved
        let removed = await assets.removed
        #expect(saved.count == 2)
        #expect(removed == saved.reversed())
    }

    @Test func removesOnlyStagedAssetsWhenAssetSaveFails() async {
        let folder = makeFolder()
        let assets = FakeAssetStore(failingOnSaveAttempt: 2)
        let service = DocumentScanService(
            pageCapturer: FakePageCapturer(
                result: .success([ScannedPage(jpegData: Data([1])), ScannedPage(jpegData: Data([2]))])
            ),
            repository: FakeRepository(folder: folder),
            assetStore: assets,
            operationSerialiser: FolderScanOperationSerialiser()
        )

        await #expect(throws: TestError.failed) {
            try await service.scanDocument(into: folder.id, named: "Scan")
        }
        #expect(await assets.removed.count == 2)
    }

    @Test func mapsNativeCancellationToCancellationError() async {
        let folder = makeFolder()
        let service = DocumentScanService(
            pageCapturer: FakePageCapturer(result: .failure(.cancelled)),
            repository: FakeRepository(folder: folder),
            assetStore: FakeAssetStore(),
            operationSerialiser: FolderScanOperationSerialiser()
        )

        await #expect(throws: CancellationError.self) {
            try await service.scanDocument(into: folder.id, named: "Scan")
        }
    }

    @Test func serializesOrderAllocationWithinFolder() async throws {
        let folder = makeFolder()
        let serialiser = FolderScanOperationSerialiser()
        let service = DocumentScanService(
            pageCapturer: FakePageCapturer(result: .success([ScannedPage(jpegData: Data([1]))])),
            repository: FakeRepository(folder: folder),
            assetStore: FakeAssetStore(),
            operationSerialiser: serialiser
        )

        async let first = service.scanDocument(into: folder.id, named: "First")
        async let second = service.scanDocument(into: folder.id, named: "Second")
        let documents = try await [first, second]

        #expect(documents.map(\.orderIndex).sorted() == [0, 1])
    }
}

@MainActor
struct NativeDocumentScannerErrorTests {
    @Test func keepsNativeFailurePrivacySafe() {
        #expect(NativeDocumentScannerError.visionKitFailure == .visionKitFailure)
    }

    @Test func completionGateDeliversOnlyFirstOutcome() {
        var outcomes: [NativeDocumentScannerError] = []
        let gate = ScanCompletionGate<NativeDocumentScannerError> { outcomes.append($0) }

        gate.takeCompletion()?(.cancelled)
        gate.takeCompletion()?(.visionKitFailure)
        gate.release()

        #expect(outcomes == [.cancelled])
    }
}

private actor FakePageCapturer: DocumentPageCapturing {
    let result: Result<[ScannedPage], NativeDocumentScannerError>
    private(set) var captureCount = 0

    init(result: Result<[ScannedPage], NativeDocumentScannerError>) {
        self.result = result
    }

    func capturePages() async throws -> [ScannedPage] {
        captureCount += 1
        return try result.get()
    }
}

private actor FakeRepository: DocumentRepository {
    let storedFolder: Folder?
    let saveDocumentError: TestError?
    private var savedDocuments: [StoredDocument] = []

    init(folder: Folder?, saveDocumentError: TestError? = nil) {
        storedFolder = folder
        self.saveDocumentError = saveDocumentError
    }

    func folder(id: UUID) async throws -> Folder? {
        storedFolder?.id == id ? storedFolder : nil
    }

    func folders() async throws -> [Folder] {
        storedFolder.map { [$0] } ?? []
    }

    func saveFolder(_ folder: Folder) async throws {}
    func document(id: UUID) async throws -> StoredDocument? {
        nil
    }

    func documents(in folderId: UUID) async throws -> [StoredDocument] {
        savedDocuments.filter { $0.folderId == folderId }
    }

    func saveDocument(_ document: StoredDocument) async throws {
        if let saveDocumentError {
            throw saveDocumentError
        }
        savedDocuments.append(document)
    }

    func moveDocument(_ document: StoredDocument) async throws {
        savedDocuments.append(document)
    }

    func deleteDocument(id: UUID) async throws {}
    func tags() async throws -> [WatakeDomain.Tag] {
        []
    }

    func saveTag(_ tag: WatakeDomain.Tag) async throws {}
    func watermarkPresets() async throws -> [WatermarkPreset] {
        []
    }

    func saveWatermarkPreset(_ preset: WatermarkPreset) async throws {}

    func trashedFolders() async throws -> [Folder] {
        []
    }

    func trashedDocuments() async throws -> [StoredDocument] {
        []
    }

    func deleteFolder(id: UUID) async throws {}

    func hasOtherReferences(to asset: AssetReference, excludingDocumentId: UUID) async throws -> Bool {
        false
    }
}

private actor FakeAssetStore: DocumentAssetStore {
    let failingOnSaveAttempt: Int?
    private(set) var saved: [AssetReference] = []
    private(set) var removed: [AssetReference] = []
    private var saveAttemptCount = 0

    init(failingOnSaveAttempt: Int? = nil) {
        self.failingOnSaveAttempt = failingOnSaveAttempt
    }

    func saveAsset(_ data: Data, reference: AssetReference) async throws {
        saveAttemptCount += 1
        if saveAttemptCount == failingOnSaveAttempt {
            throw TestError.failed
        }
        saved.append(reference)
    }

    func readAsset(_ reference: AssetReference) async throws -> Data {
        Data()
    }

    func containsAsset(_ reference: AssetReference) async throws -> Bool {
        false
    }

    func removeAsset(_ reference: AssetReference) async throws {
        removed.append(reference)
    }
}

private enum TestError: Error, Equatable, Sendable { case failed }

private func makeFolder(deletedAt: Date? = nil) -> Folder {
    Folder(id: UUID(), name: "Folder", colorHex: "#1F4FEB", createdAt: Date(), deletedAt: deletedAt)
}
