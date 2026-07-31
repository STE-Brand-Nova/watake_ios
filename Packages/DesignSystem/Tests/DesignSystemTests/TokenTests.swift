import SwiftUI
import XCTest
@testable import DesignSystem

final class TokenTests: XCTestCase {
    // MARK: - Hex parsing

    func testHexParsesSixDigits() throws {
        let rgba = try XCTUnwrap(RGBA(hex: "#1F4FEB"))
        XCTAssertEqual(rgba.red, Double(0x1F) / 255, accuracy: 0.0001)
        XCTAssertEqual(rgba.green, Double(0x4F) / 255, accuracy: 0.0001)
        XCTAssertEqual(rgba.blue, Double(0xEB) / 255, accuracy: 0.0001)
        XCTAssertEqual(rgba.alpha, 1)
    }

    func testHexParsesEightDigitAlpha() throws {
        let rgba = try XCTUnwrap(RGBA(hex: "#0B122066"))
        XCTAssertEqual(rgba.alpha, Double(0x66) / 255, accuracy: 0.0001)
    }

    func testHexWithoutHashParses() {
        XCTAssertNotNil(RGBA(hex: "FFFFFF"))
    }

    func testMalformedHexReturnsNil() {
        XCTAssertNil(RGBA(hex: "#XYZ"))
        XCTAssertNil(RGBA(hex: "#12"))
        XCTAssertNil(RGBA(hex: ""))
    }

    func testLightAndDarkComponentsDiffer() {
        let value = ColorValue(lightHex: "#FFFFFF", darkHex: "#0B0F1A")
        XCTAssertNotEqual(value.light, value.dark)
    }

    // MARK: - Spacing

    func testSpacingScaleMatchesDesign() {
        XCTAssertEqual(WatakeSpacing.scale, [4, 8, 12, 16, 20, 24, 32, 40, 48, 64])
    }

    func testSpacingIsMonotonic() {
        XCTAssertEqual(WatakeSpacing.scale, WatakeSpacing.scale.sorted())
    }

    // MARK: - Radius

    func testRadiusValues() {
        XCTAssertEqual(WatakeRadius.sm, 8)
        XCTAssertEqual(WatakeRadius.md, 12)
        XCTAssertEqual(WatakeRadius.lg, 16)
        XCTAssertEqual(WatakeRadius.xl, 24)
        XCTAssertEqual(WatakeRadius.pill, 999)
    }

    // MARK: - Typography

    func testTypographyHasEightStyles() {
        XCTAssertEqual(WatakeTypography.allCases.count, 8)
    }

    func testTypographySizesMatchDesign() {
        XCTAssertEqual(WatakeTypography.display.size, 32)
        XCTAssertEqual(WatakeTypography.title1.size, 24)
        XCTAssertEqual(WatakeTypography.title2.size, 20)
        XCTAssertEqual(WatakeTypography.body.size, 16)
        XCTAssertEqual(WatakeTypography.bodyEmphasis.size, 16)
        XCTAssertEqual(WatakeTypography.caption.size, 13)
        XCTAssertEqual(WatakeTypography.overline.size, 11)
        XCTAssertEqual(WatakeTypography.mono.size, 14)
    }

    func testOverlineIsUppercaseAndTracked() {
        XCTAssertEqual(WatakeTypography.overline.textCase, .uppercase)
        XCTAssertGreaterThan(WatakeTypography.overline.tracking, 0)
    }

    func testNonOverlineHasNoTracking() {
        for style in WatakeTypography.allCases where style != .overline {
            XCTAssertEqual(style.tracking, 0)
            XCTAssertNil(style.textCase)
        }
    }

    func testMonoUsesMonospacedDesign() {
        XCTAssertEqual(WatakeTypography.mono.design, .monospaced)
    }

    func testLineHeightsMatchDesign() {
        XCTAssertEqual(WatakeTypography.display.lineHeight, 40)
        XCTAssertEqual(WatakeTypography.title1.lineHeight, 32)
        XCTAssertEqual(WatakeTypography.title2.lineHeight, 28)
        XCTAssertEqual(WatakeTypography.body.lineHeight, 24)
        XCTAssertEqual(WatakeTypography.bodyEmphasis.lineHeight, 24)
        XCTAssertEqual(WatakeTypography.caption.lineHeight, 18)
        XCTAssertEqual(WatakeTypography.overline.lineHeight, 16)
        XCTAssertEqual(WatakeTypography.mono.lineHeight, 20)
    }

    func testLineSpacingIsLeadingAboveFontSize() {
        for style in WatakeTypography.allCases {
            XCTAssertEqual(style.lineSpacing, style.lineHeight - style.size)
            XCTAssertGreaterThanOrEqual(style.lineSpacing, 0)
        }
    }

    // MARK: - Semantic color tokens instantiate without crashing

    func testSemanticColorTokensResolve() {
        _ = [
            WatakeColor.brand.primary,
            WatakeColor.brand.primaryPressed,
            WatakeColor.brand.primaryDisabled,
            WatakeColor.surface.base,
            WatakeColor.surface.raised,
            WatakeColor.surface.sunken,
            WatakeColor.border.subtle,
            WatakeColor.border.strong,
            WatakeColor.text.primary,
            WatakeColor.text.secondary,
            WatakeColor.text.disabled,
            WatakeColor.text.onPrimary,
            WatakeColor.text.onWarning,
            WatakeColor.text.onDanger,
            WatakeColor.status.warning,
            WatakeColor.status.success,
            WatakeColor.status.danger,
            WatakeColor.scrim
        ]
    }
}
