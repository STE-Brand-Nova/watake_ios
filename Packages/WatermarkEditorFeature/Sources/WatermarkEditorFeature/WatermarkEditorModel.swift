import Foundation
import Observation
import WatakeDomain

/// Main-actor editor state with an in-memory working copy. Preview publication
/// is debounced by roughly 100 ms so future bitmap/Canvas work can remain
/// responsive while text editing never mutates the source document.
@MainActor
@Observable
public final class WatermarkEditorModel: Identifiable {
    public let id = UUID()
    public internal(set) var draft: WatermarkEditorDraft
    public var selectedTab: WatermarkEditorTab
    public private(set) var preview: WatermarkEditorPreview
    public internal(set) var imageImportState: WatermarkImageImportState = .empty
    public internal(set) var imageImportError: WatermarkImageImportError?
    public internal(set) var presetLibraryState: WatermarkPresetLibraryState = .idle
    public internal(set) var presetSaveState: WatermarkPresetSaveState = .idle
    public internal(set) var activePresetState: WatermarkActivePresetState = .none

    var colorInputs: [WatermarkTextLayerKind: String]
    var imageTintInput = ""
    private let imageImporter: any WatermarkImageImporting
    let presetStore: any WatermarkPresetStore
    let now: @Sendable () -> Date
    let makeUUID: @Sendable () -> UUID
    var imageData: Data?
    var imageImportTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    var presetTask: Task<Void, Never>?
    private var previewRevision = 0
    var draftRevision = 0
    var presetOperationRevision = 0

    public init(
        draft: WatermarkEditorDraft = .init(),
        selectedTab: WatermarkEditorTab = .heading,
        imageImporter: any WatermarkImageImporting = WatermarkImageImporter(),
        presetStore: any WatermarkPresetStore = UnavailableWatermarkPresetStore(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.draft = draft
        self.selectedTab = selectedTab
        self.imageImporter = imageImporter
        self.presetStore = presetStore
        self.now = now
        self.makeUUID = makeUUID
        preview = WatermarkEditorPreview(draft: draft, imageData: nil)
        imageTintInput = draft.image.tintHex ?? ""
        colorInputs = Dictionary(
            uniqueKeysWithValues: WatermarkTextLayerKind.allCases.map { kind in
                (kind, draft.layer(for: kind).colorHex)
            }
        )
    }

    public var previewLayers: [WatermarkEditorPreviewLayer] {
        preview.textLayers
    }

    public func imageLayer() -> EditableWatermarkImageLayer {
        draft.image
    }

    public func tintInput() -> String {
        imageTintInput
    }

    public func layer(for kind: WatermarkTextLayerKind) -> EditableWatermarkTextLayer {
        draft.layer(for: kind)
    }

    public func colorInput(for kind: WatermarkTextLayerKind) -> String {
        colorInputs[kind] ?? layer(for: kind).colorHex
    }

    public func setText(_ value: String, for kind: WatermarkTextLayerKind) {
        draft.update(kind) { $0.setText(value) }
        schedulePreview()
    }

    public func setEnabled(_ value: Bool, for kind: WatermarkTextLayerKind) {
        draft.update(kind) { $0.setEnabled(value) }
        schedulePreview()
    }

    public func setFontName(_ value: String, for kind: WatermarkTextLayerKind) {
        draft.update(kind) { $0.setFontName(value) }
        schedulePreview()
    }

    public func setSizePreset(_ value: WatermarkSizePreset, for kind: WatermarkTextLayerKind) {
        draft.update(kind) { $0.setSizePreset(value) }
        schedulePreview()
    }

    public func setColorInput(_ value: String, for kind: WatermarkTextLayerKind) {
        colorInputs[kind] = value
        let priorColor = layer(for: kind).colorHex
        draft.update(kind) { $0.setColorHex(value) }
        if layer(for: kind).colorHex != priorColor {
            schedulePreview()
        }
    }

    public func commitColorInput(for kind: WatermarkTextLayerKind) {
        colorInputs[kind] = layer(for: kind).colorHex
    }

    public func setSemanticColor(_ value: WatermarkSemanticColor, for kind: WatermarkTextLayerKind) {
        draft.update(kind) { $0.setColorHex(value.hex) }
        colorInputs[kind] = value.hex
        schedulePreview()
    }

    public func setRotation(_ value: Double, for kind: WatermarkTextLayerKind) {
        draft.update(kind) { $0.setRotation(value) }
        schedulePreview()
    }

    public func setOpacity(_ value: Double, for kind: WatermarkTextLayerKind) {
        draft.update(kind) { $0.setOpacity(value) }
        schedulePreview()
    }

    public func importImage(data: Data) {
        imageImportTask?.cancel()
        let hadImage = imageData != nil
        imageImportError = nil
        imageImportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let imported = try await imageImporter.importImage(data: data)
                guard !Task.isCancelled else { return }
                imageData = imported.data
                draft.updateImage { $0.setAssetReference(imported.assetReference) }
                imageImportState = .loaded
                schedulePreview()
            } catch is CancellationError {
                return
            } catch let error as WatermarkImageImportError {
                guard !Task.isCancelled else { return }
                imageImportError = error
                if !hadImage {
                    imageImportState = .rejected(error)
                }
            } catch {
                guard !Task.isCancelled else { return }
                imageImportError = .undecodable
                if !hadImage {
                    imageImportState = .rejected(.undecodable)
                }
            }
        }
    }

    /// Reports a picker transfer failure without exposing photo metadata.
    public func rejectImageImport() {
        imageImportError = .undecodable
        if imageData == nil {
            imageImportState = .rejected(.undecodable)
        }
    }

    public func removeImage() {
        imageImportTask?.cancel()
        imageData = nil
        imageImportError = nil
        imageImportState = .empty
        draft.updateImage { $0.clearAssetReference() }
        schedulePreview()
    }

    public func setImageEnabled(_ value: Bool) {
        draft.updateImage { $0.setEnabled(value) }
        schedulePreview()
    }

    public func setImageScale(_ value: Double) {
        draft.updateImage { $0.setScale(value) }
        schedulePreview()
    }

    public func setImageRotation(_ value: Double) {
        draft.updateImage { $0.setRotation(value) }
        schedulePreview()
    }

    public func setImageOpacity(_ value: Double) {
        draft.updateImage { $0.setOpacity(value) }
        schedulePreview()
    }

    public func setImagePlacement(_ value: WatermarkImagePlacement) {
        draft.updateImage { $0.setPlacement(value) }
        schedulePreview()
    }

    public func setImageTintEnabled(_ value: Bool) {
        draft.updateImage { $0.setTintHex(value ? WatermarkSemanticColor.ink.hex : nil) }
        imageTintInput = value ? WatermarkSemanticColor.ink.hex : ""
        schedulePreview()
    }

    public func setImageTintInput(_ value: String) {
        imageTintInput = value
        let before = draft.image.tintHex
        draft.updateImage { $0.setTintHex(value) }
        if before != draft.image.tintHex {
            schedulePreview()
        }
    }

    public func commitImageTintInput() {
        imageTintInput = draft.image.tintHex ?? ""
    }

    public func setImageSemanticTint(_ value: WatermarkSemanticColor) {
        draft.updateImage { $0.setTintHex(value.hex) }
        imageTintInput = value.hex
        schedulePreview()
    }

    public var layoutMode: WatermarkLayoutMode {
        draft.layoutMode
    }

    public var tileSpacingX: Double? {
        draft.tileSpacingX
    }

    public var tileSpacingY: Double? {
        draft.tileSpacingY
    }

    public func setLayoutMode(_ value: WatermarkLayoutMode) {
        draft.setLayoutMode(value)
        schedulePreview()
    }

    public func setTileSpacingX(_ value: Double) {
        draft.setTileSpacingX(value)
        schedulePreview()
    }

    public func setTileSpacingY(_ value: Double) {
        draft.setTileSpacingY(value)
        schedulePreview()
    }

    public func cancelPreviewWork() {
        previewTask?.cancel()
        imageImportTask?.cancel()
        presetTask?.cancel()
    }

    /// Test synchronization seam. It never performs export rendering.
    public func waitForPreview() async {
        await previewTask?.value
    }

    /// Test synchronization seam for the in-memory picker import.
    public func waitForImageImport() async {
        await imageImportTask?.value
    }

    func schedulePreview(draftDidChange: Bool = true) {
        if draftDidChange {
            draftRevision += 1
            markDraftModifiedIfNeeded()
        }
        previewRevision += 1
        let revision = previewRevision
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard let self, !Task.isCancelled, previewRevision == revision else { return }
            preview = WatermarkEditorPreview(draft: draft, imageData: imageData)
        }
    }
}

public enum WatermarkImageImportState: Equatable, Sendable {
    case empty
    case loaded
    case rejected(WatermarkImageImportError)
}
