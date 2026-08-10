import Foundation
import Testing
@testable import WatakeDomain

@Suite("ExportPageGeometry")
struct ExportPageGeometryTests {
    @Test("Exact A4 media box portrait")
    func a4Portrait() {
        let box = ExportPageGeometry.mediaBox(for: .a4, sourceWidth: 100, sourceHeight: 200)
        #expect(box.width == 595.28)
        #expect(box.height == 841.89)
    }

    @Test("Exact A4 media box landscape (for landscape source)")
    func a4Landscape() {
        let box = ExportPageGeometry.mediaBox(for: .a4, sourceWidth: 200, sourceHeight: 100)
        #expect(box.width == 841.89)
        #expect(box.height == 595.28)
    }

    @Test("Exact US Letter media box portrait")
    func usLetterPortrait() {
        let box = ExportPageGeometry.mediaBox(for: .usLetter, sourceWidth: 100, sourceHeight: 200)
        #expect(box.width == 612)
        #expect(box.height == 792)
    }

    @Test("Exact US Letter media box landscape")
    func usLetterLandscape() {
        let box = ExportPageGeometry.mediaBox(for: .usLetter, sourceWidth: 200, sourceHeight: 100)
        #expect(box.width == 792)
        #expect(box.height == 612)
    }

    @Test("Original preserves source dimensions")
    func originalDimensions() {
        let box = ExportPageGeometry.mediaBox(for: .original, sourceWidth: 123.4, sourceHeight: 567.8)
        #expect(box.width == 123.4)
        #expect(box.height == 567.8)
    }

    @Test("EXIF orientation application")
    func exifOrientation() {
        // Identity
        let id = ExportPageGeometry.appliedOrientation(rawWidth: 100, rawHeight: 200, exifOrientation: 1)
        #expect(id.width == 100 && id.height == 200 && id.isTransposed == false)

        // 90 CW (6)
        let clockwise = ExportPageGeometry.appliedOrientation(rawWidth: 100, rawHeight: 200, exifOrientation: 6)
        #expect(clockwise.width == 200 && clockwise.height == 100 && clockwise.isTransposed == true)

        // 90 CCW (8)
        let ccw = ExportPageGeometry.appliedOrientation(rawWidth: 100, rawHeight: 200, exifOrientation: 8)
        #expect(ccw.width == 200 && ccw.height == 100 && ccw.isTransposed == true)
    }

    @Test("Content rect non-zero margin correctly inset")
    func contentRectMargin() throws {
        let mediaBox = ExportPageGeometry.PageRect(x: 0, y: 0, width: 100, height: 100)
        let rect = try ExportPageGeometry.contentRect(mediaBox: mediaBox, marginPoints: 10)

        #expect(rect.x == 10)
        #expect(rect.y == 10)
        #expect(rect.width == 80)
        #expect(rect.height == 80)
    }

    @Test("Content rect zero margin equals media box")
    func contentRectZeroMargin() throws {
        let mediaBox = ExportPageGeometry.PageRect(x: 0, y: 0, width: 100, height: 100)
        let rect = try ExportPageGeometry.contentRect(mediaBox: mediaBox, marginPoints: 0)

        #expect(rect == mediaBox)
    }

    @Test("Excessive margin throws marginTooLarge error")
    func excessiveMargin() {
        let mediaBox = ExportPageGeometry.PageRect(x: 0, y: 0, width: 100, height: 100)

        do {
            _ = try ExportPageGeometry.contentRect(mediaBox: mediaBox, marginPoints: 50)
            Issue.record("Expected error")
        } catch ExportError.marginTooLarge(let margin, let width, let height) {
            #expect(margin == 50)
            #expect(width == 100)
            #expect(height == 100)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Fit mode: portrait image in landscape page")
    func fitPortraitInLandscape() {
        let contentRect = ExportPageGeometry.PageRect(x: 0, y: 0, width: 200, height: 100)
        let transform = ExportPageGeometry.fitTransform(sourceWidth: 50, sourceHeight: 100, contentRect: contentRect)

        // Scale should be 1 (limited by height 100/100)
        #expect(abs(transform.scale - 1.0) < ExportPageGeometry.tolerance)
        // tx should center horizontally: (200 - 50) / 2 = 75
        #expect(abs(transform.translateX - 75.0) < ExportPageGeometry.tolerance)
        #expect(abs(transform.translateY - 0.0) < ExportPageGeometry.tolerance)
        #expect(transform.clipRect == contentRect)
    }

    @Test("Fit mode: landscape image in portrait page")
    func fitLandscapeInPortrait() {
        let contentRect = ExportPageGeometry.PageRect(x: 0, y: 0, width: 100, height: 200)
        let transform = ExportPageGeometry.fitTransform(sourceWidth: 100, sourceHeight: 50, contentRect: contentRect)

        // Scale should be 1 (limited by width 100/100)
        #expect(abs(transform.scale - 1.0) < ExportPageGeometry.tolerance)
        // ty should center vertically: (200 - 50) / 2 = 75
        #expect(abs(transform.translateX - 0.0) < ExportPageGeometry.tolerance)
        #expect(abs(transform.translateY - 75.0) < ExportPageGeometry.tolerance)
    }

    @Test("Fill mode: scale and crop offset verification")
    func fillMode() {
        let contentRect = ExportPageGeometry.PageRect(x: 10, y: 10, width: 100, height: 100)
        // Source is wider than it is tall
        let transform = ExportPageGeometry.fillTransform(sourceWidth: 200, sourceHeight: 100, contentRect: contentRect)

        // Scale should be 1 (limited by height to fill, max of 100/200, 100/100 -> 1.0)
        #expect(abs(transform.scale - 1.0) < ExportPageGeometry.tolerance)
        // Scaled width is 200. Centering in 100 means offset of -50, plus rect.x (10) -> -40
        #expect(abs(transform.translateX - -40.0) < ExportPageGeometry.tolerance)
        #expect(abs(transform.translateY - 10.0) < ExportPageGeometry.tolerance)
        #expect(transform.clipRect == contentRect)
    }

    @Test("maxPixelDimensions returns correct downscaled size")
    func maxPixelDimensions() {
        let contentRect = ExportPageGeometry.PageRect(x: 0, y: 0, width: 100, height: 100)

        // Fit mode
        let fitDims = ExportPageGeometry.maxPixelDimensions(sourceWidth: 400, sourceHeight: 200, contentRect: contentRect, fitMode: .fit)
        // scale = 100/400 = 0.25 -> width = 100, height = 50
        #expect(fitDims.width == 100)
        #expect(fitDims.height == 50)

        // Fill mode
        let fillDims = ExportPageGeometry.maxPixelDimensions(sourceWidth: 400, sourceHeight: 200, contentRect: contentRect, fitMode: .fill)
        // scale = max(100/400, 100/200) = 0.5 -> width = 200, height = 100
        #expect(fillDims.width == 200)
        #expect(fillDims.height == 100)
    }
}
