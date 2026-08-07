import Foundation
import Testing
import WatakeDomain
@testable import WatermarkEditorFeature

struct WatermarkEditorDraftTests {
    @Test func defaultsCreateThreeOptionalDisabledTextLayers() {
        let draft = WatermarkEditorDraft()

        #expect(!draft.heading.enabled)
        #expect(!draft.body.enabled)
        #expect(!draft.caption.enabled)
        #expect(draft.heading.text.isEmpty)
        #expect(draft.body.text.isEmpty)
        #expect(draft.caption.text.isEmpty)
        #expect(draft.watermarkConfig.schemaVersion == 1)
    }

    @Test func draftCodableRoundTripPreservesContractTextLayerFields() throws {
        var draft = WatermarkEditorDraft()
        draft.update(.heading) {
            $0.setText("Private")
            $0.setEnabled(true)
            $0.setFontName("Courier")
            $0.setSizePreset(.large)
            $0.setColorHex("#1f4feb")
            $0.setRotation(30)
            $0.setOpacity(0.4)
        }

        let decoded = try JSONDecoder().decode(WatermarkEditorDraft.self, from: JSONEncoder().encode(draft))

        #expect(decoded == draft)
        #expect(decoded.heading.colorHex == "#1F4FEB")
        #expect(decoded.watermarkConfig.heading?.fontName == "Courier")
    }

    @Test func modelBoundaryClampsNumbersAndRetainsLastSafeColor() {
        var layer = EditableWatermarkTextLayer(colorHex: "#1F4FEB", rotation: 300, opacity: -1)

        #expect(layer.rotation == 180)
        #expect(layer.opacity == 0)
        layer.setRotation(-999)
        layer.setOpacity(2)
        layer.setColorHex("not a color")

        #expect(layer.rotation == -180)
        #expect(layer.opacity == 1)
        #expect(layer.colorHex == "#1F4FEB")
    }

    @Test func fontCatalogUsesVerifiedSerializableFamilyNames() {
        #expect(!WatermarkFontCatalog.supportedFontNames.contains("SF Pro"))
        #expect(WatermarkFontCatalog.sanitized("SF Pro") == WatermarkFontCatalog.defaultFontName)
        #expect(WatermarkFontCatalog.sanitized("Times New Roman") == "Times New Roman")
    }

    @Test func disabledOrEmptyLayersAreNotPreviewEligible() {
        let disabled = EditableWatermarkTextLayer(text: "Private", enabled: false)
        let empty = EditableWatermarkTextLayer(text: "   ", enabled: true)
        let visible = EditableWatermarkTextLayer(text: "Private", enabled: true)

        #expect(!disabled.isRenderable)
        #expect(!empty.isRenderable)
        #expect(visible.isRenderable)
    }

    @Test func previewCompositionAlwaysUsesHeadingBodyCaptionOrder() {
        var draft = WatermarkEditorDraft()
        for kind in WatermarkTextLayerKind.allCases {
            draft.update(kind) {
                $0.setText(kind.title)
                $0.setEnabled(true)
            }
        }

        #expect(draft.renderableLayersInCompositionOrder.map(\.kind) == [.heading, .body, .caption])
        #expect(draft.watermarkConfig.renderableTextLayersInCompositionOrder.map(\.text) == ["Heading", "Body", "Caption"])
    }

    @Test func switchingToTiledSuppliesSafeDefaultSpacing() {
        var draft = WatermarkEditorDraft()

        draft.setLayoutMode(.tiled)

        #expect(draft.layoutMode == .tiled)
        #expect(draft.tileSpacingX == WatermarkEditorDraft.defaultTileSpacingX)
        #expect(draft.tileSpacingY == WatermarkEditorDraft.defaultTileSpacingY)
    }

    @Test func switchingToSingleClearsSpacing() {
        var draft = WatermarkEditorDraft()
        draft.setLayoutMode(.tiled)
        draft.setTileSpacingX(0.5)
        draft.setTileSpacingY(0.6)

        draft.setLayoutMode(.single)

        #expect(draft.layoutMode == .single)
        #expect(draft.tileSpacingX == nil)
        #expect(draft.tileSpacingY == nil)
    }

    @Test func reenteringTiledLayoutAfterClearingUsesSafeDefaultsAgain() {
        var draft = WatermarkEditorDraft()
        draft.setLayoutMode(.tiled)
        draft.setTileSpacingX(0.5)
        draft.setTileSpacingY(0.6)
        draft.setLayoutMode(.single)

        draft.setLayoutMode(.tiled)

        #expect(draft.tileSpacingX == WatermarkEditorDraft.defaultTileSpacingX)
        #expect(draft.tileSpacingY == WatermarkEditorDraft.defaultTileSpacingY)
    }

    @Test func tileSpacingSettersClampToContractRangeAndNoOpOutsideTiledLayout() {
        var draft = WatermarkEditorDraft()
        draft.setTileSpacingX(0.5)
        draft.setTileSpacingY(0.5)
        #expect(draft.tileSpacingX == nil)
        #expect(draft.tileSpacingY == nil)

        draft.setLayoutMode(.tiled)
        draft.setTileSpacingX(5)
        draft.setTileSpacingY(-1)

        #expect(draft.tileSpacingX == 1.00)
        #expect(draft.tileSpacingY == 0.10)
    }

    @Test func draftCodableRoundTripPreservesLayoutFields() throws {
        var draft = WatermarkEditorDraft()
        draft.setLayoutMode(.tiled)
        draft.setTileSpacingX(0.42)
        draft.setTileSpacingY(0.19)

        let decoded = try JSONDecoder().decode(WatermarkEditorDraft.self, from: JSONEncoder().encode(draft))

        #expect(decoded == draft)
        #expect(decoded.watermarkConfig.layoutMode == .tiled)
        #expect(decoded.watermarkConfig.tileSpacingX == 0.42)
        #expect(decoded.watermarkConfig.tileSpacingY == 0.19)
    }

    @Test func draftDecodingLegacyJSONWithoutLayoutFieldsDefaultsToSingle() throws {
        let json = """
        {
            "heading": {},
            "body": {},
            "caption": {}
        }
        """

        let decoded = try JSONDecoder().decode(WatermarkEditorDraft.self, from: Data(json.utf8))

        #expect(decoded.layoutMode == .single)
        #expect(decoded.tileSpacingX == nil)
        #expect(decoded.tileSpacingY == nil)
    }

    @MainActor
    @Test func editingOneLayerDoesNotChangeTheOtherTwo() async {
        let model = WatermarkEditorModel()
        let originalHeading = model.layer(for: .heading)
        let originalCaption = model.layer(for: .caption)

        model.setText("Recipient: Example", for: .body)
        model.setEnabled(true, for: .body)
        model.setOpacity(0.35, for: .body)
        await model.waitForPreview()

        #expect(model.layer(for: .heading) == originalHeading)
        #expect(model.layer(for: .caption) == originalCaption)
        #expect(model.layer(for: .body).text == "Recipient: Example")
        #expect(model.previewLayers.map(\.kind) == [.body])
    }
}
