import CoreGraphics
import Testing
import WatakeDomain
@testable import DocumentProcessing

@Suite("Vision OCR geometry")
struct VisionOCRGeometryTests {
    @Test("converts lower-left Vision bounds to top-left Watake bounds")
    func convertsCoordinateOrigin() throws {
        let result = try #require(OCRVisionGeometry.topLeftNormalizedRect(from: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.25)))

        expectRect(result, originX: 0.2, originY: 0.45, width: 0.4, height: 0.25)
    }

    @Test("clamps partially out-of-range bounds and drops invalid bounds")
    func handlesInvalidBounds() throws {
        let clamped = try #require(OCRVisionGeometry.topLeftNormalizedRect(from: CGRect(x: -0.1, y: 0.6, width: 0.3, height: 0.5)))
        expectRect(clamped, originX: 0, originY: 0, width: 0.2, height: 0.4)
        #expect(OCRVisionGeometry.topLeftNormalizedRect(from: CGRect(x: 1.1, y: 0, width: 0.2, height: 0.2)) == nil)
        #expect(OCRVisionGeometry.topLeftNormalizedRect(from: CGRect(x: .nan, y: 0, width: 0.2, height: 0.2)) == nil)
    }

    private func expectRect(_ rect: NormalizedRect, originX: Double, originY: Double, width: Double, height: Double) {
        #expect(abs(rect.originX - originX) < 0.000_001)
        #expect(abs(rect.originY - originY) < 0.000_001)
        #expect(abs(rect.width - width) < 0.000_001)
        #expect(abs(rect.height - height) < 0.000_001)
    }
}
