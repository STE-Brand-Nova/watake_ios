import XCTest
@testable import DesignSystem

/// WCAG 4.5:1 body-text contrast checks for the chip label. The chip label uses
/// `WatakeColor.text.primary`; the tint colors only the background/border, so
/// text must stay readable over the composited chip background in both
/// appearances.
final class ContrastTests: XCTestCase {
    private let minimumBodyContrast = 4.5

    /// Tint tokens a chip may receive.
    private let tints: [(String, ColorValue)] = [
        ("brand", ColorValue(lightHex: "#1F4FEB", darkHex: "#4C7BFF")),
        ("warning", ColorValue(lightHex: "#F59E0B", darkHex: "#FBBF24")),
        ("success", ColorValue(lightHex: "#047857", darkHex: "#34D399")),
        ("danger", ColorValue(lightHex: "#B91C1C", darkHex: "#F87171"))
    ]

    private let textPrimary = ColorValue(lightHex: "#0B1220", darkHex: "#F5F7FB")
    private let surfaceBase = ColorValue(lightHex: "#FFFFFF", darkHex: "#0B0F1A")
    private let surfaceRaised = ColorValue(lightHex: "#F6F7FB", darkHex: "#141A2A")

    private func chipBackground(tint: RGBA, over surface: RGBA) -> RGBA {
        // Matches WatakeTagChip: tint filled at 12% opacity over the surface.
        RGBA(red: tint.red, green: tint.green, blue: tint.blue, alpha: 0.12)
            .composited(over: surface)
    }

    func testChipLabelPassesContrastLight() {
        for surface in [surfaceBase.light, surfaceRaised.light] {
            for (name, tint) in tints {
                let background = chipBackground(tint: tint.light, over: surface)
                let ratio = textPrimary.light.contrastRatio(against: background)
                XCTAssertGreaterThanOrEqual(
                    ratio, minimumBodyContrast,
                    "light chip label over \(name) tint: \(ratio)"
                )
            }
        }
    }

    func testChipLabelPassesContrastDark() {
        for surface in [surfaceBase.dark, surfaceRaised.dark] {
            for (name, tint) in tints {
                let background = chipBackground(tint: tint.dark, over: surface)
                let ratio = textPrimary.dark.contrastRatio(against: background)
                XCTAssertGreaterThanOrEqual(
                    ratio, minimumBodyContrast,
                    "dark chip label over \(name) tint: \(ratio)"
                )
            }
        }
    }

    /// A counter-example: using the tint itself as the label color can fail 4.5:1,
    /// which is exactly why the chip does not do that.
    func testTintAsLabelCanFailContrast() throws {
        let warning = try XCTUnwrap(tints.first { $0.0 == "warning" }).1.light
        let background = chipBackground(tint: warning, over: surfaceBase.light)
        XCTAssertLessThan(warning.contrastRatio(against: background), minimumBodyContrast)
    }

    // Sanity: known WCAG anchors.
    func testBlackWhiteContrastIsTwentyOne() throws {
        let white = try XCTUnwrap(RGBA(hex: "#FFFFFF"))
        let black = try XCTUnwrap(RGBA(hex: "#000000"))
        XCTAssertEqual(white.contrastRatio(against: black), 21, accuracy: 0.01)
    }
}
