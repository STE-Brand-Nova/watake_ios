import Foundation
import Testing
import WatakeDomain
import XCTest
@testable import DocumentProcessing

private actor ResidencyTracker {
    private(set) var activeReads = 0
    private(set) var maxConcurrentReads = 0

    func enterRead() {
        activeReads += 1
        if activeReads > maxConcurrentReads {
            maxConcurrentReads = activeReads
        }
    }

    func exitRead() {
        activeReads -= 1
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isPassed = false

    func wait() async {
        if isPassed {
            return
        }
        await withCheckedContinuation { cont in
            continuation = cont
        }
    }

    func pass() {
        isPassed = true
        continuation?.resume()
        continuation = nil
    }
}

private final class TrackingAssetStore: DocumentAssetStore, @unchecked Sendable {
    private let mockStore = BulkPDFRendererTests.MockAssetStore()
    fileprivate let tracker = ResidencyTracker()
    fileprivate let gate = AsyncGate()
    /// Signalled the moment the paused page's read begins, so tests can wait
    /// for "page N entered" deterministically instead of sleeping.
    fileprivate let enteredGate = AsyncGate()
    var pauseOnPageID: UUID?

    func setMockData(_ pageID: UUID, data: Data) async {
        await mockStore.setMockData(pageID, data: data)
    }

    func saveAsset(_ data: Data, reference: AssetReference) async throws {}
    func containsAsset(_ reference: AssetReference) async throws -> Bool {
        true
    }

    func removeAsset(_ reference: AssetReference) async throws {}

    func readAsset(_ reference: AssetReference) async throws -> Data {
        await tracker.enterRead()
        if reference.id == pauseOnPageID {
            await enteredGate.pass()
            await gate.wait()
        }
        let data = try await mockStore.readAsset(reference)
        await tracker.exitRead()
        return data
    }
}

@Suite("BulkPDFRenderer Memory & Performance")
struct PDFRendererMemoryTests {
    private func makeJob(pages: [PDFRenderPage]) -> PDFRenderJob {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        return PDFRenderJob(
            pages: pages,
            pageSize: .a4,
            fitMode: .fit,
            marginPoints: 0,
            outputURL: tempURL
        )
    }

    private func makePage(id: UUID = UUID()) -> PDFRenderPage {
        PDFRenderPage(
            id: id,
            assetReference: AssetReference(id: id, relativePath: "test.jpg", sha256Hex: "abc", byteSize: 2048, mediaType: nil)
        )
    }

    @Test
    func serialAssetReadsAndPerformanceMetrics() async throws {
        let store = TrackingAssetStore()
        let pages = (0 ..< 10).map { _ in makePage() }
        for page in pages {
            await store.setMockData(page.id, data: BulkPDFRendererTests.MockAssetStore.generateJPEG(width: 1200, height: 1600))
        }

        let clock = ContinuousClock()
        let renderer = BulkPDFRenderer(assetStore: store)

        let elapsed = try await clock.measure {
            for _ in 0 ..< 3 {
                let job = makeJob(pages: pages)
                let outputURL = try await renderer.renderPDF(job: job) { _ in }
                #expect(FileManager.default.fileExists(atPath: outputURL.path))
                try FileManager.default.removeItem(at: outputURL)
            }
        }

        // The renderer must read assets one at a time, never overlapping asset
        // loads across pages. This bounds how many source Data buffers are held
        // concurrently; it does NOT prove decoded-CGImage lifetime or bounded
        // peak memory, which would require instrumenting renderPage directly.
        let maxConcurrent = await store.tracker.maxConcurrentReads
        #expect(maxConcurrent <= 1)
        #expect(elapsed < .seconds(10))
    }

    @Test
    func cancellationRaceConditionActiveProcessingCleanup() async throws {
        let store = TrackingAssetStore()
        let page1 = makePage()
        let page2 = makePage()
        store.pauseOnPageID = page2.id

        await store.setMockData(page1.id, data: BulkPDFRendererTests.MockAssetStore.generateJPEG(width: 800, height: 800))
        await store.setMockData(page2.id, data: BulkPDFRendererTests.MockAssetStore.generateJPEG(width: 800, height: 800))

        let job = makeJob(pages: [page1, page2])
        let renderer = BulkPDFRenderer(assetStore: store)

        let task = Task {
            try await renderer.renderPDF(job: job) { _ in }
        }

        // Wait deterministically until page 2's read has entered and paused at
        // the gate (page 1 already completed, since reads are serial).
        await store.enteredGate.wait()

        // Cancel while renderer is actively blocked waiting inside page 2 processing
        task.cancel()
        // Unblock gate so task wakes up and detects cancellation
        await store.gate.pass()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        // Assert partial output file was removed
        #expect(!FileManager.default.fileExists(atPath: job.outputURL.path))
    }
}

final class PDFRendererPerformanceXCTests: XCTestCase {
    func testExportPerformanceMetrics() {
        let store = BulkPDFRendererTests.MockAssetStore()
        // Page id and asset id must match: the renderer reads mock data by
        // assetReference.id, but setMockData keys by page.id. Distinct UUIDs
        // would silently fall back to the 100x100 default and skip the
        // configured 600x800 workload.
        let page1ID = UUID()
        let page2ID = UUID()
        let page1 = PDFRenderPage(
            id: page1ID,
            assetReference: AssetReference(id: page1ID, relativePath: "p1.jpg", sha256Hex: "123", byteSize: 500)
        )
        let page2 = PDFRenderPage(
            id: page2ID,
            assetReference: AssetReference(id: page2ID, relativePath: "p2.jpg", sha256Hex: "456", byteSize: 500)
        )

        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let exp = expectation(description: "Render PDF")
            Task {
                await store.setMockData(page1.id, data: BulkPDFRendererTests.MockAssetStore.generateJPEG(width: 600, height: 800))
                await store.setMockData(page2.id, data: BulkPDFRendererTests.MockAssetStore.generateJPEG(width: 600, height: 800))

                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
                let job = PDFRenderJob(pages: [page1, page2], pageSize: .a4, fitMode: .fit, marginPoints: 0, outputURL: tempURL)

                let renderer = BulkPDFRenderer(assetStore: store)
                let url = try await renderer.renderPDF(job: job) { _ in }
                try? FileManager.default.removeItem(at: url)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5.0)
        }
    }
}
