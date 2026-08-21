import Foundation
import Testing
import WatakeDomain
@testable import WatermarkEditorFeature

struct WatermarkPresetTests {
    @Test func presetNamesTrimAndValidateOneToOneHundredTwentyCharacters() {
        #expect(WatermarkPresetNameValidation.validate("  Company A  ") == .valid("Company A"))
        #expect(WatermarkPresetNameValidation.validate(" \n ") == .empty)
        #expect(WatermarkPresetNameValidation.validate(String(repeating: "a", count: 121)) == .tooLong)
    }

    @MainActor
    @Test func libraryOrdersNamesCaseInsensitivelyAndReportsEmptyLoadingStates() async {
        let store = MemoryPresetStore(presets: [preset(name: "zeta"), preset(name: "Alpha"), preset(name: "beta")])
        let model = WatermarkEditorModel(presetStore: store)

        model.loadPresets()
        #expect(model.presetLibraryState == .loading)
        await model.waitForPresetWork()

        guard case .loaded(let items) = model.presetLibraryState else {
            Issue.record("Expected loaded presets")
            return
        }
        #expect(items.map(\.preset.name) == ["Alpha", "beta", "zeta"])

        let emptyModel = WatermarkEditorModel(presetStore: MemoryPresetStore())
        emptyModel.loadPresets()
        await emptyModel.waitForPresetWork()
        #expect(emptyModel.presetLibraryState == .empty)
    }

    @MainActor
    @Test func duplicateNamesConflictAfterTrimmingWithoutStorageWrite() async {
        let store = MemoryPresetStore(presets: [preset(name: "Company A")])
        let model = WatermarkEditorModel(presetStore: store)

        model.savePreset(named: "  company a  ")
        await model.waitForPresetWork()

        #expect(model.presetSaveState == .conflict)
        #expect(await store.saveCount() == 0)
    }

    @MainActor
    @Test func storageDuplicateNameErrorMapsToConflict() async {
        let model = WatermarkEditorModel(presetStore: DuplicateSavingPresetStore())

        model.savePreset(named: "Company A")
        await model.waitForPresetWork()

        #expect(model.presetSaveState == .conflict)
    }

    @MainActor
    @Test func libraryFailureReportsSafeState() async {
        let model = WatermarkEditorModel(presetStore: MemoryPresetStore(fails: true))

        model.loadPresets()
        await model.waitForPresetWork()

        #expect(model.presetLibraryState == .failure)
    }

    @MainActor
    @Test func saveUsesImmutableConfigSnapshotAndSetsCleanActivePreset() async throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let store = MemoryPresetStore()
        let model = WatermarkEditorModel(presetStore: store, now: { date }, makeUUID: { id })
        model.setText("Recipient", for: .body)
        model.setEnabled(true, for: .body)
        let snapshot = model.draft.watermarkConfig

        model.savePreset(named: "  Company A  ")
        await model.waitForPresetWork()

        #expect(model.presetSaveState == .saved)
        #expect(model.activePresetState == .selected(id: id, name: "Company A"))
        #expect(await store.presets() == [WatermarkPreset(id: id, name: "Company A", config: snapshot, createdAt: date, updatedAt: date)])

        model.setText("Changed", for: .body)
        #expect(model.activePresetState == .modified(id: id, name: "Company A"))
        #expect(await (store.presets()).first?.config == snapshot)
    }

    @MainActor
    @Test func applyCreatesIndependentEditableDraftAndClearsTransientImageState() {
        let stored = preset(name: "Reusable", body: "Original")
        let model = WatermarkEditorModel(presetStore: MemoryPresetStore())
        model.applyPreset(.init(preset: stored))

        #expect(model.draft.watermarkConfig.body == stored.config.body)
        #expect(model.activePresetState == .selected(id: stored.id, name: stored.name))
        model.setText("Changed", for: .body)

        #expect(model.draft.watermarkConfig != stored.config)
        #expect(stored.config.body?.text == "Original")
        #expect(model.activePresetState == .modified(id: stored.id, name: stored.name))
    }

    @MainActor
    @Test func savingAndApplyingATiledPresetPreservesLayoutConfiguration() async {
        let store = MemoryPresetStore()
        let model = WatermarkEditorModel(presetStore: store)
        model.setText("Recipient", for: .body)
        model.setEnabled(true, for: .body)
        model.setLayoutMode(.tiled)
        model.setTileSpacingX(0.42)
        model.setTileSpacingY(0.19)

        model.savePreset(named: "Tiled preset")
        await model.waitForPresetWork()

        #expect(model.presetSaveState == .saved)
        guard let saved = await store.presets().first else {
            Issue.record("Expected saved preset")
            return
        }
        #expect(saved.config.layoutMode == .tiled)
        #expect(saved.config.tileSpacingX == 0.42)
        #expect(saved.config.tileSpacingY == 0.19)

        let freshModel = WatermarkEditorModel(presetStore: MemoryPresetStore())
        freshModel.applyPreset(.init(preset: saved))

        #expect(freshModel.layoutMode == .tiled)
        #expect(freshModel.tileSpacingX == 0.42)
        #expect(freshModel.tileSpacingY == 0.19)
    }

    @MainActor
    @Test func imageBearingDraftCannotSaveAndDoesNotWriteStorage() async {
        let draft = WatermarkEditorDraft(image: .init(assetReference: imageReference()))
        let store = MemoryPresetStore()
        let model = WatermarkEditorModel(draft: draft, presetStore: store)

        model.savePreset(named: "Image preset")

        #expect(model.presetSaveState == .imageUnsupported)
        #expect(await store.saveCount() == 0)
    }

    @MainActor
    @Test func imageBearingStoredPresetAppliesAndLoadsItsAsset() async {
        let reference = imageReference()
        let stored = WatermarkPreset(
            id: UUID(),
            name: "Image",
            config: config(body: "Other", image: reference),
            createdAt: .now,
            updatedAt: .now
        )
        let model = WatermarkEditorModel(
            presetStore: MemoryPresetStore(),
            assetStore: MemoryAssetStore(values: [reference.id: Data([0])])
        )
        let item = WatermarkPresetLibraryItem(preset: stored)

        #expect(item.isAvailable)
        model.applyPreset(item)
        await model.waitForPresetWork()

        #expect(model.draft.watermarkConfig.body == stored.config.body)
        #expect(model.draft.watermarkConfig.image == stored.config.image)
        #expect(model.watermarkImageData() == Data([0]))
        #expect(model.activePresetState == .selected(id: stored.id, name: stored.name))
    }

    @MainActor
    @Test func libraryMarksStoredImagePresetAvailable() async {
        let imagePreset = WatermarkPreset(
            id: UUID(),
            name: "Image",
            config: config(body: "", image: imageReference()),
            createdAt: .now,
            updatedAt: .now
        )
        let model = WatermarkEditorModel(presetStore: MemoryPresetStore(presets: [imagePreset]))

        model.loadPresets()
        await model.waitForPresetWork()

        guard case .loaded(let items) = model.presetLibraryState else {
            Issue.record("Expected loaded presets")
            return
        }
        #expect(items == [.init(preset: imagePreset)])
        #expect(items[0].isAvailable)
    }

    @MainActor
    @Test func storageFailurePreservesDraftAndReportsSafeFailure() async {
        let draft = WatermarkEditorDraft(body: .init(text: "Keep", enabled: true))
        let model = WatermarkEditorModel(draft: draft, presetStore: MemoryPresetStore(fails: true))

        model.savePreset(named: "Company")
        await model.waitForPresetWork()

        #expect(model.presetSaveState == .failure)
        #expect(model.draft == draft)
    }

    @MainActor
    @Test func staleAsyncLoadCannotReplaceNewerAppliedDraft() async {
        let store = MemoryPresetStore(presets: [preset(name: "Stale")], delay: .milliseconds(100))
        let newer = preset(name: "Newer", body: "Newer text")
        let model = WatermarkEditorModel(presetStore: store)

        model.loadPresets()
        model.applyPreset(.init(preset: newer))
        await model.waitForPresetWork()

        #expect(model.draft.watermarkConfig.body == newer.config.body)
        #expect(model.activePresetState == .selected(id: newer.id, name: newer.name))
    }
}

private actor MemoryPresetStore: WatermarkPresetStore {
    private var values: [WatermarkPreset]
    private var writes = 0
    private let fails: Bool
    private let delay: Duration?

    init(presets: [WatermarkPreset] = [], fails: Bool = false, delay: Duration? = nil) {
        values = presets
        self.fails = fails
        self.delay = delay
    }

    func watermarkPresets() async throws -> [WatermarkPreset] {
        if let delay {
            try? await Task.sleep(for: delay)
        }
        if fails {
            throw WatermarkPresetStoreError.unavailable
        }
        return values
    }

    func saveWatermarkPreset(_ preset: WatermarkPreset) async throws {
        if fails {
            throw WatermarkPresetStoreError.unavailable
        }
        guard !values.contains(where: {
            $0.id != preset.id && $0.name.caseInsensitiveCompare(preset.name) == .orderedSame
        }) else {
            throw WatermarkPresetStoreError.duplicateName
        }
        writes += 1
        values.append(preset)
    }

    func presets() -> [WatermarkPreset] {
        values
    }

    func saveCount() -> Int {
        writes
    }
}

private struct DuplicateSavingPresetStore: WatermarkPresetStore {
    func watermarkPresets() async throws -> [WatermarkPreset] {
        []
    }

    func saveWatermarkPreset(_ preset: WatermarkPreset) async throws {
        throw WatermarkPresetStoreError.duplicateName
    }
}

private actor MemoryAssetStore: DocumentAssetStore {
    private var values: [UUID: Data]

    init(values: [UUID: Data] = [:]) {
        self.values = values
    }

    func saveAsset(_ data: Data, reference: AssetReference) async throws {
        values[reference.id] = data
    }

    func readAsset(_ reference: AssetReference) async throws -> Data {
        guard let data = values[reference.id] else { throw WatermarkPresetStoreError.unavailable }
        return data
    }

    func containsAsset(_ reference: AssetReference) async throws -> Bool {
        values[reference.id] != nil
    }

    func removeAsset(_ reference: AssetReference) async throws {
        values[reference.id] = nil
    }
}

private func preset(name: String, body: String = "") -> WatermarkPreset {
    WatermarkPreset(id: UUID(), name: name, config: config(body: body), createdAt: .now, updatedAt: .now)
}

private func config(
    body: String,
    image: AssetReference? = nil,
    layoutMode: WatermarkLayoutMode = .single,
    tileSpacingX: Double? = nil,
    tileSpacingY: Double? = nil
) -> WatermarkConfig {
    WatermarkConfig(
        automatic: false,
        body: .init(
            text: body,
            enabled: !body.isEmpty,
            fontName: "Helvetica",
            sizePreset: .medium,
            colorHex: "#0B1220",
            rotation: 0,
            opacity: 1
        ),
        image: image.map {
            WatermarkImageLayer(
                enabled: true,
                assetRef: $0,
                scale: 1,
                rotation: 0,
                opacity: 1,
                placement: .behindText
            )
        },
        globalPosition: .center,
        globalRotation: 0,
        globalOpacity: 1,
        layoutMode: layoutMode,
        tileSpacingX: tileSpacingX,
        tileSpacingY: tileSpacingY
    )
}

private func imageReference() -> AssetReference {
    AssetReference(
        id: UUID(),
        relativePath: "watermark-assets/test.png",
        sha256Hex: String(repeating: "a", count: 64),
        byteSize: 1,
        mediaType: "image/png"
    )
}
