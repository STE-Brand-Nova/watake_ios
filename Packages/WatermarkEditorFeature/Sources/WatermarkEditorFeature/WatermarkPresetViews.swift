#if canImport(UIKit)
    import DesignSystem
    import SwiftUI

    struct WatermarkPresetActions: View {
        @Bindable var model: WatermarkEditorModel
        @State private var isSaving = false
        @State private var isBrowsing = false

        var body: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                HStack(spacing: WatakeSpacing.sm) {
                    Button("Apply Preset") {
                        isBrowsing = true
                        model.loadPresets()
                    }
                    .buttonStyle(.watake(.secondary))
                    .accessibilityHint("Opens saved watermark presets")

                    Button("Save Preset") {
                        model.resetPresetSaveState()
                        isSaving = true
                    }
                    .buttonStyle(.watake(.secondary))
                    .accessibilityHint("Saves this in-memory watermark configuration")
                }
                if model.presetSaveState == .saved {
                    WatakeTagChip("Preset saved", color: WatakeColor.status.success)
                        .accessibilityLabel("Preset saved")
                }
                if model.draft.watermarkConfig.image != nil {
                    Text("Image presets will be available after image assets can be saved.")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.secondary)
                        .accessibilityLabel("Image presets unavailable")
                }
            }
            .sheet(isPresented: $isSaving) {
                WatermarkSavePresetSheet(model: model)
            }
            .sheet(isPresented: $isBrowsing) {
                WatermarkPresetLibrarySheet(model: model) {
                    isBrowsing = false
                }
            }
        }
    }

    struct WatermarkPresetStatusPill: View {
        let state: WatermarkActivePresetState

        var body: some View {
            WatakeTagChip(state.label, color: statusColor)
                .accessibilityLabel("Preset status")
                .accessibilityValue(state.label)
        }

        private var statusColor: Color {
            switch state {
            case .none: WatakeColor.text.secondary
            case .selected: WatakeColor.status.success
            case .modified: WatakeColor.status.warning
            }
        }
    }

    private struct WatermarkSavePresetSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: WatermarkEditorModel
        @State private var name = ""
        @FocusState private var isNameFocused: Bool

        private var nameValidation: WatermarkPresetNameValidation {
            WatermarkPresetNameValidation.validate(name)
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Preset name", text: $name)
                            .textInputAutocapitalization(.words)
                            .focused($isNameFocused)
                            .accessibilityLabel("Preset name")
                            .accessibilityHint("Names must be between 1 and 120 characters")
                        if let message = validationMessage {
                            Text(message)
                                .watakeType(.caption)
                                .foregroundStyle(WatakeColor.status.danger)
                                .accessibilityLabel("Preset validation")
                                .accessibilityValue(message)
                        }
                    } header: {
                        Text("Save current configuration")
                    } footer: {
                        if model.draft.watermarkConfig.image != nil {
                            Text("Image presets will be available after image assets can be saved.")
                        } else {
                            Text("Saving does not apply or export a watermark.")
                        }
                    }
                }
                .navigationTitle("Save Preset")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { model.savePreset(named: name) }
                            .disabled(!canSave)
                    }
                }
                .onAppear { isNameFocused = true }
                .onChange(of: model.presetSaveState) { _, state in
                    if state == .saved {
                        dismiss()
                    }
                }
            }
            .presentationDetents([.medium])
        }

        private var canSave: Bool {
            if case .valid = nameValidation {
                return model.draft.watermarkConfig.image == nil && model.presetSaveState != .saving
            }
            return false
        }

        private var validationMessage: String? {
            if case .idle = model.presetSaveState {
                return nameValidation.message
            }
            switch model.presetSaveState {
            case .invalidName(let validation): return validation.message
            case .conflict: return "A preset with this name already exists."
            case .imageUnsupported: return "Image presets will be available after image assets can be saved."
            case .failure: return "Preset could not be saved. Try again."
            case .idle, .saving, .saved: return nameValidation.message
            }
        }
    }

    private struct WatermarkPresetLibrarySheet: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: WatermarkEditorModel
        let onApply: () -> Void

        var body: some View {
            NavigationStack {
                Group {
                    switch model.presetLibraryState {
                    case .idle, .loading:
                        ProgressView("Loading presets")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("Loading presets")
                    case .empty:
                        WatakeEmptyState(
                            systemImage: "bookmark",
                            title: "No presets yet.",
                            message: "Save a configuration to reuse it later."
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        WatakeEmptyState(
                            systemImage: "exclamationmark.triangle",
                            title: "Couldn't load presets.",
                            message: "Try again.",
                            actionTitle: "Retry"
                        ) {
                            model.loadPresets()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .loaded(let items):
                        List(items) { item in
                            WatermarkPresetRow(item: item) {
                                model.applyPreset(item)
                                dismiss()
                                onApply()
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                .navigationTitle("Apply Preset")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .task { model.loadPresets() }
        }
    }

    private struct WatermarkPresetRow: View {
        let item: WatermarkPresetLibraryItem
        let apply: () -> Void

        var body: some View {
            Button(action: apply) {
                VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
                    Text(item.preset.name)
                        .watakeType(.bodyEmphasis)
                        .foregroundStyle(WatakeColor.text.primary)
                    if item.isAvailable {
                        Text(item.accessibilitySummary)
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.secondary)
                    } else {
                        Text("Unavailable: image asset is not stored yet.")
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(!item.isAvailable)
            .accessibilityLabel(item.preset.name)
            .accessibilityValue(item.isAvailable ? item.accessibilitySummary : "Unavailable image preset")
            .accessibilityHint(item.isAvailable ? "Applies an editable copy" : "Image presets cannot be applied yet")
        }
    }
#endif
