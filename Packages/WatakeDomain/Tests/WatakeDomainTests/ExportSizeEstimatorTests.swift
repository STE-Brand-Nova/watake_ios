import Foundation
import Testing
@testable import WatakeDomain

@Suite("ExportSizeEstimator")
struct ExportSizeEstimatorTests {
    @Test("DefaultExportSizeEstimator estimate below threshold")
    func estimateBelowThreshold() {
        let estimator = DefaultExportSizeEstimator(perPageOverheadBytes: 2048, compressionFactor: 1.1)
        let page1 = makeRenderPage(byteSize: 10_000_000)
        let page2 = makeRenderPage(byteSize: 10_000_000)

        let estimate = estimator.estimateOutputSize(pages: [page1, page2], pageSize: .a4, fitMode: .fit)

        let expectedAssetSize = 20_000_000
        let expectedWithCompression = Int(Double(expectedAssetSize) * 1.1)
        let expectedOverhead = 2 * 2048

        #expect(estimate == expectedWithCompression + expectedOverhead)
    }

    @Test("ExportWarningPolicy shouldWarn behavior")
    func warningPolicyShouldWarn() {
        let policy = ExportWarningPolicy(thresholdBytes: 50_000_000) // 50 MB

        #expect(policy.shouldWarn(estimatedBytes: 10_000_000) == false)
        #expect(policy.shouldWarn(estimatedBytes: 50_000_000) == true) // exactly at threshold
        #expect(policy.shouldWarn(estimatedBytes: 60_000_000) == true)
    }

    @Test("ExportWarningPolicy custom threshold")
    func customThreshold() {
        let policy = ExportWarningPolicy(thresholdBytes: 1024)
        #expect(policy.shouldWarn(estimatedBytes: 1023) == false)
        #expect(policy.shouldWarn(estimatedBytes: 1025) == true)
    }

    private func makeRenderPage(byteSize: Int) -> PDFRenderPage {
        let asset = AssetReference(
            id: UUID(),
            relativePath: "test.jpg",
            sha256Hex: String(repeating: "a", count: 64),
            byteSize: byteSize
        )
        return PDFRenderPage(id: UUID(), assetReference: asset)
    }
}
