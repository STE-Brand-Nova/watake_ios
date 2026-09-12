#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain

    struct HighlightDrawControls: View {
        @Bindable var model: DocumentEditorModel

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WatakeSpacing.sm) {
                    Text("Highlight color")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.secondary)
                    ForEach(DocumentEditorPalette.highlightColors, id: \.self) { hex in
                        HighlightColorButton(
                            hex: hex,
                            isSelected: model.highlightColorHex == hex,
                            action: { model.setHighlightDrawingColor(hex) }
                        )
                    }
                    Divider().frame(height: 28)
                    Button {
                        model.setHighlightAutoStraighten(!model.autoStraightenHighlights)
                    } label: {
                        Label(
                            "Auto-straighten",
                            systemImage: model.autoStraightenHighlights ? "checkmark.circle.fill" : "circle"
                        )
                        .watakeType(.caption)
                        .foregroundStyle(
                            model.autoStraightenHighlights ? WatakeColor.brand.primary : WatakeColor.text.secondary
                        )
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(model.autoStraightenHighlights ? "On" : "Off")
                }
                .padding(.horizontal, WatakeSpacing.sm)
            }
            .frame(minHeight: 52)
            .background(WatakeColor.surface.raised)
            .overlay(alignment: .top) { Divider() }
        }
    }

    struct HighlightStyleSheet: View {
        @Bindable var model: DocumentEditorModel
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    Section("Color") {
                        HStack(spacing: WatakeSpacing.sm) {
                            ForEach(DocumentEditorPalette.highlightColors, id: \.self) { hex in
                                HighlightColorButton(
                                    hex: hex,
                                    isSelected: selectedStroke?.colorHex == hex,
                                    action: { update(colorHex: hex) }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Section("Appearance") {
                        VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                            Text("Opacity")
                                .watakeType(.caption)
                                .foregroundStyle(WatakeColor.text.secondary)
                            Slider(
                                value: Binding(
                                    get: { selectedStroke?.opacity ?? model.highlightOpacity },
                                    set: { update(opacity: $0) }
                                ),
                                in: 0 ... 1,
                                onEditingChanged: handleContinuousEdit
                            )
                            .accessibilityValue("\(Int((selectedStroke?.opacity ?? model.highlightOpacity) * 100)) percent")
                        }
                        VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                            Text("Stroke thickness")
                                .watakeType(.caption)
                                .foregroundStyle(WatakeColor.text.secondary)
                            Slider(
                                value: Binding(
                                    get: { selectedStroke?.width ?? model.highlightWidth },
                                    set: { update(width: $0) }
                                ),
                                in: 0.008 ... 0.06,
                                onEditingChanged: handleContinuousEdit
                            )
                        }
                    }
                }
                .navigationTitle("Highlight Style")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }

        private var selectedStroke: InkStroke? {
            model.selectedAnnotation?.kind == .highlight ? model.selectedAnnotation?.strokes.first : nil
        }

        private func update(width: Double? = nil, colorHex: String? = nil, opacity: Double? = nil) {
            guard let selectedStroke else { return }
            model.updateSelectedStrokeStyle(
                width: width ?? selectedStroke.width,
                colorHex: colorHex ?? selectedStroke.colorHex,
                opacity: opacity ?? selectedStroke.opacity
            )
        }

        private func handleContinuousEdit(_ isEditing: Bool) {
            if isEditing {
                model.beginContinuousEdit()
            } else {
                model.endContinuousEdit()
            }
        }
    }

    private struct HighlightColorButton: View {
        let hex: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Circle()
                    .fill(highlightColor(hex))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Circle().stroke(
                            isSelected ? WatakeColor.brand.primary : WatakeColor.border.strong,
                            lineWidth: isSelected ? 3 : 1
                        )
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose highlight color \(hex)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private func highlightColor(_ hex: String) -> Color {
        guard hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return WatakeColor.status.warning }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
#endif
