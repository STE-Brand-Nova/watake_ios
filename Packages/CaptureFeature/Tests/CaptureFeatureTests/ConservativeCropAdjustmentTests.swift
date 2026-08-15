import Foundation
import Testing
import WatakeDomain
@testable import CaptureFeature

@MainActor
struct ConservativeCropAdjustmentTests {
    @Test
    func autoAdjustResolvesOnlyModeratelyReliableUncertainPages() async throws {
        let detectedQuad = CropQuadrilateral(
            topLeft: NormalizedPoint(x: 0.2, y: 0.8),
            topRight: NormalizedPoint(x: 0.8, y: 0.8),
            bottomRight: NormalizedPoint(x: 0.8, y: 0.2),
            bottomLeft: NormalizedPoint(x: 0.2, y: 0.2)
        )
        let state = CaptureReviewState(pages: [
            CaptureReviewPage(
                sourceData: Data("recoverable".utf8),
                cropQuadrilateral: detectedQuad,
                detectionUncertain: true
            ),
            CaptureReviewPage(
                sourceData: Data("ambiguous".utf8),
                cropQuadrilateral: detectedQuad,
                detectionUncertain: true
            )
        ])

        state.autoAdjustUncertainPages(via: AutoAdjustmentRectifier(quadrilateral: detectedQuad))
        try await Task.sleep(for: .milliseconds(20))

        #expect(!state.isProcessing)
        #expect(state.uncertainPageCount == 1)
        #expect(state.autoAdjustmentSummary?.adjustedPageCount == 1)
        #expect(state.autoAdjustmentSummary?.manualReviewPageCount == 1)
        #expect(state.pages[0].wasAutoCropAdjusted)
        #expect(!state.pages[0].detectionUncertain)
        #expect(state.pages[0].rectifiedData == Data("auto-rectified".utf8))
        #expect(state.pages[0].cropQuadrilateral?.topLeft.x ?? 1 < detectedQuad.topLeft.x)
        #expect(state.pages[0].cropQuadrilateral?.topLeft.y ?? 0 > detectedQuad.topLeft.y)
        #expect(!state.pages[1].wasAutoCropAdjusted)
        #expect(state.pages[1].detectionUncertain)
        #expect(state.pages[1].rectifiedData == nil)
    }
}

private struct AutoAdjustmentRectifier: DocumentRectifying {
    let quadrilateral: CropQuadrilateral

    func detect(in jpegData: Data) async -> RectificationResult {
        RectificationResult(
            quadrilateral: quadrilateral,
            isDetectionConfident: false,
            confidence: jpegData == Data("recoverable".utf8) ? 0.75 : 0.64
        )
    }

    func rectify(jpegData: Data, quadrilateral: CropQuadrilateral, rotationDegrees: Int) async -> Data? {
        Data("auto-rectified".utf8)
    }
}
