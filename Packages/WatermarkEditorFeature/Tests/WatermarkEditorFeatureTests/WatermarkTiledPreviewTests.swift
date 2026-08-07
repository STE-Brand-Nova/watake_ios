import Foundation
import Testing
import WatakeDomain
@testable import WatermarkEditorFeature

@MainActor
struct WatermarkTiledPreviewTests {
    @Test func singleLayoutPreviewHasExactlyOneTile() async {
        let model = WatermarkEditorModel()

        await model.waitForPreview()

        #expect(model.preview.layoutMode == .single)
        #expect(model.preview.tileCount == 1)
    }

    @Test func tiledLayoutPreviewTileCountMatchesCalculator() async {
        let model = WatermarkEditorModel()

        model.setLayoutMode(.tiled)
        await model.waitForPreview()

        let expected = WatermarkTileLayoutCalculator.tilePoints(
            tileSpacingX: WatermarkEditorDraft.defaultTileSpacingX,
            tileSpacingY: WatermarkEditorDraft.defaultTileSpacingY
        )

        #expect(model.preview.layoutMode == .tiled)
        #expect(model.preview.tileCount == expected.count)
        #expect(model.preview.tilePoints == expected)
    }

    @Test func narrowingSpacingIncreasesTileCountUpToTheHardCap() async {
        let model = WatermarkEditorModel()
        model.setLayoutMode(.tiled)

        model.setTileSpacingX(0.10)
        model.setTileSpacingY(0.10)
        await model.waitForPreview()

        #expect(model.preview.tileCount == WatermarkTileLayoutCalculator.maximumTileCount)
    }

    @Test func layoutEditsPreserveTextAndImageDraftState() async {
        let model = WatermarkEditorModel()
        model.setText("Recipient: Example", for: .body)
        model.setEnabled(true, for: .body)
        let bodyBefore = model.layer(for: .body)
        let imageBefore = model.imageLayer()

        model.setLayoutMode(.tiled)
        model.setTileSpacingX(0.5)
        await model.waitForPreview()

        #expect(model.layer(for: .body) == bodyBefore)
        #expect(model.imageLayer() == imageBefore)
    }

    @Test func layoutEditsMarkAppliedPresetAsModified() {
        let store = LayoutPresetStore()
        let preset = WatermarkPreset(
            id: UUID(),
            name: "Reusable",
            config: WatermarkConfig(
                automatic: false,
                body: .init(
                    text: "Body",
                    enabled: true,
                    fontName: "Helvetica",
                    sizePreset: .medium,
                    colorHex: "#0B1220",
                    rotation: 0,
                    opacity: 1
                ),
                globalPosition: .center,
                globalRotation: 0,
                globalOpacity: 1
            ),
            createdAt: .now,
            updatedAt: .now
        )
        let model = WatermarkEditorModel(presetStore: store)
        model.applyPreset(.init(preset: preset))
        #expect(model.activePresetState == .selected(id: preset.id, name: preset.name))

        model.setLayoutMode(.tiled)

        #expect(model.activePresetState == .modified(id: preset.id, name: preset.name))
    }
}

private struct LayoutPresetStore: WatermarkPresetStore {
    func watermarkPresets() async throws -> [WatermarkPreset] {
        []
    }

    func saveWatermarkPreset(_ preset: WatermarkPreset) async throws {}
}
