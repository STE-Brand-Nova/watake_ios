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
    public private(set) var draft: WatermarkEditorDraft
    public var selectedTab: WatermarkEditorTab
    public private(set) var previewLayers: [WatermarkEditorPreviewLayer]

    private var colorInputs: [WatermarkTextLayerKind: String]
    private var previewTask: Task<Void, Never>?
    private var previewRevision = 0

    public init(draft: WatermarkEditorDraft = .init(), selectedTab: WatermarkEditorTab = .heading) {
        self.draft = draft
        self.selectedTab = selectedTab
        previewLayers = draft.renderableLayersInCompositionOrder
        colorInputs = Dictionary(
            uniqueKeysWithValues: WatermarkTextLayerKind.allCases.map { kind in
                (kind, draft.layer(for: kind).colorHex)
            }
        )
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

    public func cancelPreviewWork() {
        previewTask?.cancel()
    }

    /// Test synchronization seam. It never performs export rendering.
    public func waitForPreview() async {
        await previewTask?.value
    }

    private func schedulePreview() {
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
            previewLayers = draft.renderableLayersInCompositionOrder
        }
    }
}
