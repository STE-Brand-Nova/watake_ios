//
//  ExportFeatureModelTests.swift
//  ExportFeatureTests
//

import Foundation
import Testing
import WatakeDomain
@testable import ExportFeature

struct MockExportDocumentLoading: ExportDocumentLoading, Sendable {
    var documentsToReturn: [StoredDocument] = []

    func documents(ids: Set<UUID>) async throws -> [StoredDocument] {
        documentsToReturn.filter { ids.contains($0.id) }
    }
}

/// A gate that a test can await and a loader can signal exactly once. Used to
/// prove behaviour while a load is suspended, without timing-based sleeps.
private actor LoaderGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isPassed = false

    func wait() async {
        if isPassed {
            return
        }
        await withCheckedContinuation { continuation = $0 }
    }

    func pass() {
        isPassed = true
        continuation?.resume()
        continuation = nil
    }
}

/// Loader that signals when `documents(ids:)` is entered, then blocks until
/// released. Lets a test deterministically cancel while loading is suspended.
private struct BlockingExportDocumentLoading: ExportDocumentLoading, Sendable {
    let documentsToReturn: [StoredDocument]
    let entered: LoaderGate
    let release: LoaderGate

    func documents(ids: Set<UUID>) async throws -> [StoredDocument] {
        await entered.pass()
        await release.wait()
        return documentsToReturn.filter { ids.contains($0.id) }
    }
}

struct MockBulkPDFExporting: BulkPDFExporting, Sendable {
    var shouldFail = false
    var shouldBeSlow = false
    var customData: Data?

    func renderPDF(
        job: PDFRenderJob,
        progress: @Sendable (ExportProgress) -> Void
    ) async throws -> URL {
        if shouldFail {
            throw ExportError.pdfContextFailed
        }

        let dataToWrite = customData ?? Data("mock pdf".utf8)
        try dataToWrite.write(to: job.outputURL)

        for pageIndex in 0 ..< job.pages.count {
            if shouldBeSlow {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try Task.checkCancellation()
            progress(ExportProgress(completedPages: pageIndex + 1, totalPages: job.pages.count, phase: .rendering(pageIndex: pageIndex)))
        }

        progress(ExportProgress(completedPages: job.pages.count, totalPages: job.pages.count, phase: .finishing))
        return job.outputURL
    }
}

struct MockExportSizeEstimating: ExportSizeEstimating, Sendable {
    var sizePerPage = 1000

    func estimateOutputSize(
        pages: [PDFRenderPage],
        pageSize: ExportPageSize,
        fitMode: ExportFitMode
    ) -> Int {
        pages.count * sizePerPage
    }
}

@MainActor
@Suite("Export Feature Model Tests")
struct ExportFeatureModelTests {
    private func createMockDocument(id: UUID = UUID(), orderIndex: Int = 0) -> StoredDocument {
        let pageID = UUID()
        let assetRef = AssetReference(id: UUID(), relativePath: "test.jpg", sha256Hex: "abc", byteSize: 100)
        let page = DocumentPage(id: pageID, index: 0, source: assetRef)
        return StoredDocument(
            id: id,
            folderId: UUID(),
            name: "Mock Doc",
            createdAt: Date(),
            updatedAt: Date(),
            orderIndex: orderIndex,
            pages: [page],
            deletedAt: nil,
            tagIds: [],
            watermarkPresetId: nil
        )
    }

    @Test func prepareDraftSuccess() async throws {
        let doc1 = createMockDocument()
        let doc2 = createMockDocument()

        let loader = MockExportDocumentLoading(documentsToReturn: [doc1, doc2])
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: MockBulkPDFExporting(),
            sizeEstimator: MockExportSizeEstimating(),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc1.id, doc2.id])

        // Wait for task to finish
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(model.state == ExportFeatureModel.State.reviewing)
        let draft = try #require(model.draft)
        #expect(draft.items.count == 2)
    }

    @Test func prepareDraftEmpty() async throws {
        let loader = MockExportDocumentLoading(documentsToReturn: [])
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: MockBulkPDFExporting(),
            sizeEstimator: MockExportSizeEstimating(),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [UUID()])

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(model.state == ExportFeatureModel.State.failed(.noPages))
        #expect(model.draft == nil)
    }

    @Test func testToggleInclusion() async throws {
        let doc = createMockDocument()
        let loader = MockExportDocumentLoading(documentsToReturn: [doc])
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: MockBulkPDFExporting(),
            sizeEstimator: MockExportSizeEstimating(),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        let pageID = doc.pages[0].id
        #expect(model.draft?.canExport == true)

        model.toggleInclusion(pageID: pageID)
        #expect(model.draft?.items[0].isIncluded == false)
        #expect(model.draft?.canExport == false)

        model.toggleInclusion(pageID: pageID)
        #expect(model.draft?.items[0].isIncluded == true)
        #expect(model.draft?.canExport == true)
    }

    @Test func testMovePage() async throws {
        let doc1 = createMockDocument(orderIndex: 0)
        let doc2 = createMockDocument(orderIndex: 1)
        let loader = MockExportDocumentLoading(documentsToReturn: [doc1, doc2])
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: MockBulkPDFExporting(),
            sizeEstimator: MockExportSizeEstimating(),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc1.id, doc2.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        let page1ID = doc1.pages[0].id
        let page2ID = doc2.pages[0].id

        model.movePage(from: IndexSet(integer: 0), to: 2)

        #expect(model.draft?.items[0].id == page2ID)
        #expect(model.draft?.items[1].id == page1ID)
    }

    @Test func moveUpAndDown() async throws {
        let doc1 = createMockDocument(orderIndex: 0)
        let doc2 = createMockDocument(orderIndex: 1)
        let loader = MockExportDocumentLoading(documentsToReturn: [doc1, doc2])
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: MockBulkPDFExporting(),
            sizeEstimator: MockExportSizeEstimating(),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc1.id, doc2.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        let page1ID = doc1.pages[0].id
        let page2ID = doc2.pages[0].id

        // Move second up
        model.movePageUp(pageID: page2ID)
        #expect(model.draft?.items[0].id == page2ID)

        // Move it back down
        model.movePageDown(pageID: page2ID)
        #expect(model.draft?.items[1].id == page2ID)

        // Boundary check
        model.movePageUp(pageID: page1ID)
        #expect(model.draft?.items[0].id == page1ID) // No change
    }

    @Test func startExportSmall() async throws {
        let doc = createMockDocument()
        let loader = MockExportDocumentLoading(documentsToReturn: [doc])
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: MockBulkPDFExporting(),
            sizeEstimator: MockExportSizeEstimating(sizePerPage: 1000),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        model.startExport()

        // Ensure it doesn't go to warning state
        if case .preflightWarning = model.state {
            Issue.record("Should not warn for small export")
        }
    }

    @Test func startExportLarge() async throws {
        let doc = createMockDocument()
        let loader = MockExportDocumentLoading(documentsToReturn: [doc])
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: MockBulkPDFExporting(),
            sizeEstimator: MockExportSizeEstimating(sizePerPage: 6000), // Exceeds 5000 threshold
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        model.startExport()

        #expect(model.state == ExportFeatureModel.State.preflightWarning(estimatedBytes: 6000))

        model.confirmLargeExport()

        if case .preflightWarning = model.state {
            Issue.record("Should have transitioned out of warning")
        }
    }

    @Test func testCancelWarning() async throws {
        let doc = createMockDocument()
        let loader = MockExportDocumentLoading(documentsToReturn: [doc])
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: MockBulkPDFExporting(),
            sizeEstimator: MockExportSizeEstimating(sizePerPage: 6000),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        model.startExport()
        #expect(model.state == ExportFeatureModel.State.preflightWarning(estimatedBytes: 6000))

        model.cancelWarning()
        #expect(model.state == ExportFeatureModel.State.reviewing)
    }

    @Test func testCancelExport() async throws {
        let doc = createMockDocument()
        let loader = MockExportDocumentLoading(documentsToReturn: [doc])
        let exporter = MockBulkPDFExporting(shouldBeSlow: true)
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: exporter,
            sizeEstimator: MockExportSizeEstimating(),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        model.startExport()

        // Let it start rendering
        try await Task.sleep(nanoseconds: 10_000_000)

        model.cancelExport()
        #expect(model.state == ExportFeatureModel.State.cancelled)
    }

    @Test func exportSuccess() async throws {
        let doc = createMockDocument()
        let loader = MockExportDocumentLoading(documentsToReturn: [doc])
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: MockBulkPDFExporting(),
            sizeEstimator: MockExportSizeEstimating(),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        model.startExport()

        // Wait for export to finish
        try await Task.sleep(nanoseconds: 100_000_000)

        if case .completed = model.state {
            // Success
        } else {
            Issue.record("Expected completed state, got \(String(describing: model.state))")
        }
    }

    @Test func exportFailure() async throws {
        let doc = createMockDocument()
        let loader = MockExportDocumentLoading(documentsToReturn: [doc])
        let exporter = MockBulkPDFExporting(shouldFail: true)
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: exporter,
            sizeEstimator: MockExportSizeEstimating(),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        model.startExport()

        // Wait for export to fail
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(model.state == ExportFeatureModel.State.failed(.renderFailed))

        model.retry()
        #expect(model.state == ExportFeatureModel.State.reviewing)
    }

    @Test func settings() async throws {
        let doc = createMockDocument()
        let loader = MockExportDocumentLoading(documentsToReturn: [doc])
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: MockBulkPDFExporting(),
            sizeEstimator: MockExportSizeEstimating(),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        model.setPageSize(.usLetter)
        model.setFitMode(.fill)
        model.setMargin(36)

        #expect(model.draft?.pageSize == .usLetter)
        #expect(model.draft?.fitMode == .fill)
        #expect(model.draft?.marginPoints == 36)
    }
}

@MainActor
@Suite("Export Feature Model Lifecycle Tests")
struct ExportFeatureModelLifecycleTests {
    private func createMockDocument(id: UUID = UUID(), orderIndex: Int = 0) -> StoredDocument {
        let pageID = UUID()
        let assetRef = AssetReference(id: UUID(), relativePath: "test.jpg", sha256Hex: "abc", byteSize: 100)
        let page = DocumentPage(id: pageID, index: 0, source: assetRef)
        return StoredDocument(
            id: id,
            folderId: UUID(),
            name: "Mock Doc",
            createdAt: Date(),
            updatedAt: Date(),
            orderIndex: orderIndex,
            pages: [page],
            deletedAt: nil,
            tagIds: [],
            watermarkPresetId: nil
        )
    }

    @Test func postRenderActualSizeWarning() async throws {
        let doc = createMockDocument()
        let loader = MockExportDocumentLoading(documentsToReturn: [doc])
        let largeData = Data(repeating: 0x41, count: 10000)
        let exporter = MockBulkPDFExporting(customData: largeData)

        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: exporter,
            sizeEstimator: MockExportSizeEstimating(sizePerPage: 1000), // Preflight estimate 1000 < 5000 threshold
            warningPolicy: ExportWarningPolicy(thresholdBytes: 5000)
        )

        model.prepareDraft(documentIDs: [doc.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        model.startExport()
        try await Task.sleep(nanoseconds: 100_000_000)

        var createdURL: URL?
        // State should be .actualSizeWarning because actual bytes (10,000) > threshold (5000)
        if case .actualSizeWarning(let bytes, let url) = model.state {
            #expect(bytes == 10000)
            createdURL = url
        } else {
            Issue.record("Expected .actualSizeWarning, got \(model.state)")
        }

        let fileURL = try #require(createdURL)
        let parentDir = fileURL.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        model.confirmActualSizeExport()
        if case .completed = model.state {
            // Success
        } else {
            Issue.record("Expected .completed state after confirming actual size warning")
        }

        model.cleanup()
        #expect(!FileManager.default.fileExists(atPath: parentDir.path))
    }

    @Test func cleanupRemovesContainingDirectory() async throws {
        let doc = createMockDocument()
        let loader = MockExportDocumentLoading(documentsToReturn: [doc])
        let exporter = MockBulkPDFExporting()

        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: exporter,
            sizeEstimator: MockExportSizeEstimating(sizePerPage: 1000),
            warningPolicy: ExportWarningPolicy(thresholdBytes: 50000)
        )

        model.prepareDraft(documentIDs: [doc.id])
        try await Task.sleep(nanoseconds: 50_000_000)

        model.startExport()
        try await Task.sleep(nanoseconds: 100_000_000)

        var createdURL: URL?
        if case .completed(let url, _) = model.state {
            createdURL = url
        }
        let fileURL = try #require(createdURL)
        let parentDir = fileURL.deletingLastPathComponent()

        #expect(FileManager.default.fileExists(atPath: parentDir.path))

        model.cleanup()
        #expect(!FileManager.default.fileExists(atPath: parentDir.path))
        #expect(model.state == .idle)
    }

    @Test func preparationCancellationRace() async throws {
        let doc = createMockDocument()
        let entered = LoaderGate()
        let release = LoaderGate()
        let loader = BlockingExportDocumentLoading(
            documentsToReturn: [doc],
            entered: entered,
            release: release
        )
        let model = ExportFeatureModel(
            documentLoader: loader,
            exporter: MockBulkPDFExporting()
        )

        model.prepareDraft(documentIDs: [doc.id])

        // Wait until the loader is actually suspended inside documents(ids:),
        // then cancel. This proves cancellation lands during a suspended load,
        // not merely after an instant loader already returned.
        await entered.wait()
        model.cancelExport()
        #expect(model.state == .cancelled)

        // Release the load so the prepare task resumes and observes the
        // cancellation. It must bail out without overwriting .cancelled or
        // publishing a draft.
        await release.pass()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(model.state == .cancelled)
        #expect(model.draft == nil)
    }
}
