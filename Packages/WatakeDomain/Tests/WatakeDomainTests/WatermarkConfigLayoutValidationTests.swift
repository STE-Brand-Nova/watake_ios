import Foundation
import Testing
@testable import WatakeDomain

@Suite("Watermark config layout validation")
struct WatermarkConfigLayoutValidationTests {
    @Test("tiled watermark layout requires both spacing values")
    func tiledLayoutRequiresSpacing() {
        let config = makeWatermarkConfig(layoutMode: .tiled)

        expectValidationError(.tileSpacingRequiredForTiledLayout) {
            try config.validate()
        }
    }

    @Test("tiled watermark layout requires vertical spacing when horizontal is set")
    func tiledLayoutRequiresVerticalSpacing() {
        let config = makeWatermarkConfig(layoutMode: .tiled, tileSpacingX: 0.35)

        expectValidationError(.tileSpacingRequiredForTiledLayout) {
            try config.validate()
        }
    }

    @Test("single watermark layout rejects non-nil spacing")
    func singleLayoutRejectsSpacing() {
        let config = makeWatermarkConfig(layoutMode: .single, tileSpacingX: 0.35, tileSpacingY: 0.28)

        expectValidationError(.tileSpacingMustBeNilForSingleLayout) {
            try config.validate()
        }
    }

    @Test("tiled watermark spacing must stay within contract range", arguments: [0.05, 1.5])
    func tiledSpacingOutOfRange(_ value: Double) {
        let config = makeWatermarkConfig(layoutMode: .tiled, tileSpacingX: value, tileSpacingY: 0.28)

        expectValidationError(.tileSpacingOutOfRange(value)) {
            try config.validate()
        }
    }

    /// NaN and infinity fail `==` under synthesized Equatable, so these are
    /// matched by case rather than by associated value.
    @Test("tiled watermark spacing rejects non-finite values", arguments: [Double.nan, Double.infinity, -Double.infinity])
    func tiledSpacingRejectsNonFiniteValues(_ value: Double) {
        let config = makeWatermarkConfig(layoutMode: .tiled, tileSpacingX: value, tileSpacingY: 0.28)

        do {
            try config.validate()
            Issue.record("Expected tileSpacingOutOfRange")
        } catch DomainValidationError.tileSpacingOutOfRange {
            // expected
        } catch {
            Issue.record("Expected tileSpacingOutOfRange, got \(error)")
        }
    }

    @Test("valid tiled watermark config round-trips through contract Codable")
    func tiledWatermarkConfigRoundTrips() throws {
        let config = makeWatermarkConfig(layoutMode: .tiled, tileSpacingX: 0.35, tileSpacingY: 0.28)

        let data = try WatakeContractCoding.makeJSONEncoder().encode(config)
        let decoded = try WatakeContractCoding.makeJSONDecoder().decode(WatermarkConfig.self, from: data)

        #expect(decoded == config)
    }

    @Test("single layout watermark config encodes as legacy JSON shape omitting all three layout fields")
    func singleLayoutWatermarkConfigEncodesWithoutLayoutFields() throws {
        let config = makeWatermarkConfig(layoutMode: .single)

        let data = try WatakeContractCoding.makeJSONEncoder().encode(config)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["layoutMode"] == nil)
        #expect(object["tileSpacingX"] == nil)
        #expect(object["tileSpacingY"] == nil)
    }

    @Test("watermark config JSON omitting layout fields decodes as single with nil spacing")
    func legacyWatermarkConfigDecodesAsSingleLayout() throws {
        let json = """
        {
            "schemaVersion": 1,
            "automatic": true,
            "body": {
                "text": "Verification",
                "enabled": true,
                "fontName": "Helvetica",
                "sizePreset": "medium",
                "colorHex": "#000000",
                "rotation": 0,
                "opacity": 0.5
            },
            "globalPosition": "center",
            "globalRotation": 0,
            "globalOpacity": 0.5
        }
        """

        let decoded = try decode(WatermarkConfig.self, from: json)

        #expect(decoded.layoutMode == .single)
        #expect(decoded.tileSpacingX == nil)
        #expect(decoded.tileSpacingY == nil)
    }
}
