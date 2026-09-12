#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain

    struct HighlightDrawControls: View {
        @Bindable var model: DocumentEditorModel
        @Binding var showsGuide: Bool
        let showStyle: () -> Void
        let dismissGuide: () -> Void

        var body: some View {
            HStack(spacing: WatakeSpacing.xs) {
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
                    .padding(.leading, WatakeSpacing.sm)
                }
                Divider().frame(height: 32)
                Button {
                    showsGuide = false
                    showStyle()
                } label: {
                    VStack(spacing: WatakeSpacing.xxs) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Style").watakeType(.overline)
                    }
                    .foregroundStyle(WatakeColor.brand.primary)
                    .frame(minWidth: 52, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Highlight Style")
                .popover(isPresented: $showsGuide, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    HighlightGuide(showStyle: showStyle, dismiss: dismissGuide)
                        .presentationCompactAdaptation(.popover)
                }
                .padding(.trailing, WatakeSpacing.xs)
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
                    Section {
                        Label(
                            selectedStroke == nil
                                ? "Changes apply to new highlights."
                                : "Changes apply to the selected highlight.",
                            systemImage: selectedStroke == nil ? "highlighter" : "hand.point.up.left"
                        )
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.secondary)
                    }
                    Section("Color") {
                        HStack(spacing: WatakeSpacing.sm) {
                            ForEach(DocumentEditorPalette.highlightColors, id: \.self) { hex in
                                HighlightColorButton(
                                    hex: hex,
                                    isSelected: currentColorHex == hex,
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
                                    get: { currentOpacity },
                                    set: { update(opacity: $0) }
                                ),
                                in: 0 ... 1,
                                onEditingChanged: handleContinuousEdit
                            )
                            .accessibilityValue("\(Int(currentOpacity * 100)) percent")
                        }
                        VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                            Text("Stroke thickness")
                                .watakeType(.caption)
                                .foregroundStyle(WatakeColor.text.secondary)
                            Slider(
                                value: Binding(
                                    get: { currentWidth },
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

        private var currentWidth: Double {
            selectedStroke?.width ?? model.highlightWidth
        }

        private var currentColorHex: String {
            selectedStroke?.colorHex ?? model.highlightColorHex
        }

        private var currentOpacity: Double {
            selectedStroke?.opacity ?? model.highlightOpacity
        }

        private func update(width: Double? = nil, colorHex: String? = nil, opacity: Double? = nil) {
            let updatedWidth = width ?? currentWidth
            let updatedColor = colorHex ?? currentColorHex
            let updatedOpacity = opacity ?? currentOpacity
            if selectedStroke != nil {
                model.updateSelectedStrokeStyle(
                    width: updatedWidth,
                    colorHex: updatedColor,
                    opacity: updatedOpacity
                )
            } else {
                model.setHighlightDrawingStyle(
                    width: updatedWidth,
                    colorHex: updatedColor,
                    opacity: updatedOpacity
                )
            }
        }

        private func handleContinuousEdit(_ isEditing: Bool) {
            guard selectedStroke != nil else { return }
            if isEditing {
                model.beginContinuousEdit()
            } else {
                model.endContinuousEdit()
            }
        }
    }

    private struct HighlightGuide: View {
        let showStyle: () -> Void
        let dismiss: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.md) {
                Text("Highlight tips")
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                guideRow(
                    icon: "arrow.left.and.right",
                    text: "Draw horizontally or vertically. Auto-straighten locks to your starting direction."
                )
                guideRow(
                    icon: "hand.point.up.left",
                    text: "To move or edit a highlight, switch to View and tap it."
                )
                guideRow(
                    icon: "slider.horizontal.3",
                    text: "Open Highlight Style for color, opacity, and thickness."
                )
                HStack {
                    Button("Got it", action: dismiss)
                        .frame(minHeight: 44)
                    Spacer()
                    Button("Open Highlight Style") {
                        dismiss()
                        showStyle()
                    }
                    .fontWeight(.semibold)
                    .frame(minHeight: 44)
                }
            }
            .padding(WatakeSpacing.md)
            .frame(idealWidth: 320)
            .background(WatakeColor.surface.raised)
        }

        private func guideRow(icon: String, text: String) -> some View {
            Label {
                Text(text)
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.primary)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(WatakeColor.brand.primary)
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
