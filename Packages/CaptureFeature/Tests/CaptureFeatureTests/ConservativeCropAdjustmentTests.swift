import Foundation
import Testing
import WatakeDomain
@testable import CaptureFeature

@MainActor
struct ConservativeCropAdjustmentTests {
    @Test
    func autoAdjustResolvesOnlyModeratelyReliableUncertainPages() async throws {
        let detectedQuad = Self.detectedQuad
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
        #expect(state.autoAdjustmentSummary?.strategy == .balanced)
        #expect(state.canRetryAggressively)
    }

    @Test
    func aggressiveRetryResolvesPagesTheBalancedPassRejected() async throws {
        let state = CaptureReviewState(pages: [
            CaptureReviewPage(
                sourceData: Data("ambiguous".utf8),
                cropQuadrilateral: Self.detectedQuad,
                detectionUncertain: true
            )
        ])
        let rectifier = AutoAdjustmentRectifier(quadrilateral: Self.detectedQuad)

        state.autoAdjustUncertainPages(via: rectifier)
        try await Task.sleep(for: .milliseconds(20))

        #expect(state.pages[0].detectionUncertain)
        #expect(state.canRetryAggressively)

        state.autoAdjustUncertainPages(via: rectifier, strategy: .aggressive)
        try await Task.sleep(for: .milliseconds(20))

        #expect(!state.isProcessing)
        #expect(state.uncertainPageCount == 0)
        #expect(state.pages[0].wasAutoCropAdjusted)
        #expect(state.autoAdjustmentSummary?.adjustedPageCount == 1)
        #expect(state.autoAdjustmentSummary?.strategy == .aggressive)
        // The stronger pass exhausts escalation: nothing left to offer.
        #expect(!state.canRetryAggressively)
    }

    @Test
    func aggressiveRetryIsNotOfferedBeforeTheBalancedPassRuns() {
        let state = CaptureReviewState(pages: [
            CaptureReviewPage(
                sourceData: Data("ambiguous".utf8),
                cropQuadrilateral: Self.detectedQuad,
                detectionUncertain: true
            )
        ])

        #expect(!state.canRetryAggressively)
    }

    @Test
    func aggressiveRetryStillReportsFailureWhenNoBoundaryExists() async throws {
        let state = CaptureReviewState(pages: [
            CaptureReviewPage(
                sourceData: Data("hopeless".utf8),
                cropQuadrilateral: .unit,
                detectionUncertain: true
            )
        ])

        state.autoAdjustUncertainPages(
            via: AutoAdjustmentRectifier(quadrilateral: Self.detectedQuad),
            strategy: .aggressive
        )
        try await Task.sleep(for: .milliseconds(20))

        #expect(state.pages[0].detectionUncertain)
        #expect(state.autoAdjustmentSummary?.adjustedPageCount == 0)
        // Escalation already spent; the user is told to fix corners by hand.
        #expect(!state.canRetryAggressively)
    }

    @Test
    func edgeTouchingCandidateIsRejectedRatherThanReportedAsAdjusted() {
        // The outset pushes every corner past the unit square, where
        // `NormalizedPoint` clamps it back to a full-image crop that would
        // change nothing the user can see.
        let detection = RectificationResult(
            quadrilateral: .unit,
            isDetectionConfident: false,
            confidence: 0.9
        )

        #expect(ConservativeCropAdjustment.make(from: detection) == nil)
        #expect(ConservativeCropAdjustment.make(from: detection, strategy: .aggressive) == nil)
    }

    @Test
    func aggressiveStrategyAcceptsWeakerCandidatesThanBalanced() {
        let detection = RectificationResult(
            quadrilateral: Self.detectedQuad,
            isDetectionConfident: false,
            confidence: 0.4
        )

        #expect(ConservativeCropAdjustment.make(from: detection) == nil)
        #expect(ConservativeCropAdjustment.make(from: detection, strategy: .aggressive) != nil)
    }

    @Test
    func aggressiveStrategyTrimsCloserToTheDetectedBoundary() throws {
        let detection = RectificationResult(
            quadrilateral: Self.detectedQuad,
            isDetectionConfident: false,
            confidence: 0.9
        )
        let balanced = try #require(ConservativeCropAdjustment.make(from: detection))
        let aggressive = try #require(
            ConservativeCropAdjustment.make(from: detection, strategy: .aggressive)
        )

        #expect(aggressive.topLeft.x > balanced.topLeft.x)
        #expect(aggressive.topLeft.y < balanced.topLeft.y)
    }

    private static let detectedQuad = CropQuadrilateral(
        topLeft: NormalizedPoint(x: 0.2, y: 0.8),
        topRight: NormalizedPoint(x: 0.8, y: 0.8),
        bottomRight: NormalizedPoint(x: 0.8, y: 0.2),
        bottomLeft: NormalizedPoint(x: 0.2, y: 0.2)
    )
}

/// Mirrors the real rectifier's behavior: the balanced pass only reports a
/// usable candidate for a clean page, while the aggressive pass also recovers
/// a weaker one. A page with no boundary at all stays unresolved either way.
private struct AutoAdjustmentRectifier: DocumentRectifying {
    let quadrilateral: CropQuadrilateral

    func detect(in jpegData: Data) async -> RectificationResult {
        await detect(in: jpegData, strategy: .balanced)
    }

    func detect(in jpegData: Data, strategy: DetectionStrategy) async -> RectificationResult {
        guard jpegData != Data("hopeless".utf8) else {
            return RectificationResult(quadrilateral: .unit, isDetectionConfident: false)
        }
        let isRecoverable = jpegData == Data("recoverable".utf8)
        let confidence: Double = if isRecoverable {
            0.75
        } else {
            strategy == .aggressive ? 0.5 : 0.64
        }
        return RectificationResult(
            quadrilateral: quadrilateral,
            isDetectionConfident: false,
            confidence: confidence
        )
    }

    func rectify(jpegData: Data, quadrilateral: CropQuadrilateral, rotationDegrees: Int) async -> Data? {
        Data("auto-rectified".utf8)
    }
}
