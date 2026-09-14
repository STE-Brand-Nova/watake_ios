#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain

    struct TextEntryOverlay: View {
        let title: String
        let onCancel: () -> Void
        let onSave: (String) -> Void
        @State private var text: String
        @FocusState private var isFocused: Bool

        init(title: String, initialText: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
            self.title = title
            self.onCancel = onCancel
            self.onSave = onSave
            _text = State(initialValue: initialText)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.md) {
                Text(title).watakeType(.title2)
                TextEditor(text: $text)
                    .focused($isFocused)
                    .frame(minHeight: 112, maxHeight: 180)
                    .padding(WatakeSpacing.xs)
                    .scrollContentBackground(.hidden)
                    .background(WatakeColor.surface.sunken)
                    .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
                    .accessibilityLabel("Text content")
                    .onChange(of: text) { _, value in
                        if value.count > AnnotationText.maximumLength {
                            text = String(value.prefix(AnnotationText.maximumLength))
                        }
                    }
                Text("\(text.count) / \(AnnotationText.maximumLength)")
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                HStack {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Save") { onSave(text) }
                        .buttonStyle(.borderedProminent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(WatakeSpacing.md)
            .frame(maxWidth: 420)
            .background(WatakeColor.surface.raised)
            .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: WatakeRadius.lg)
                    .stroke(WatakeColor.border.strong, lineWidth: 1)
            }
            .task { isFocused = true }
        }
    }

    struct TextStyleSheet: View {
        @Bindable var model: DocumentEditorModel
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    if let text = model.selectedAnnotation?.text {
                        VStack(alignment: .leading, spacing: WatakeSpacing.lg) {
                            fontFamily(text)
                            fontSize(text)
                            emphasis(text)
                            textColor(text)
                            layerOrder
                        }
                        .padding(WatakeSpacing.md)
                    } else {
                        ContentUnavailableView("No text selected", systemImage: "textformat")
                    }
                }
                .background(WatakeColor.surface.base)
                .navigationTitle("Text style")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }

        private func fontFamily(_ text: AnnotationText) -> some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Font family").watakeType(.bodyEmphasis)
                Picker("Font family", selection: Binding(
                    get: { model.selectedAnnotation?.text?.fontName ?? "Helvetica" },
                    set: { update(text, fontName: $0) }
                )) {
                    ForEach(["Helvetica", "Georgia", "Courier"], id: \.self) { font in
                        Text(font).font(.custom(font, size: 17)).tag(font)
                    }
                }
                .pickerStyle(.segmented)
            }
        }

        private func fontSize(_ text: AnnotationText) -> some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                HStack {
                    Text("Font size").watakeType(.bodyEmphasis)
                    Spacer()
                    Text("\(displaySize(text))")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.secondary)
                }
                Slider(value: Binding(
                    get: { model.selectedAnnotation?.text?.fontSize ?? text.fontSize },
                    set: { update(text, size: $0) }
                ), in: 0.01 ... 0.15)
                    .accessibilityValue("\(displaySize(text))")
            }
        }

        private func emphasis(_ text: AnnotationText) -> some View {
            HStack(spacing: WatakeSpacing.sm) {
                Toggle("Bold", isOn: Binding(
                    get: { model.selectedAnnotation?.text?.isBold ?? text.isBold },
                    set: { update(text, bold: $0) }
                ))
                Toggle("Italic", isOn: Binding(
                    get: { model.selectedAnnotation?.text?.isItalic ?? text.isItalic },
                    set: { update(text, italic: $0) }
                ))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
        }

        private func textColor(_ text: AnnotationText) -> some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Text color").watakeType(.bodyEmphasis)
                HStack(spacing: WatakeSpacing.sm) {
                    ForEach(DocumentEditorPalette.textColors, id: \.self) { hex in
                        Button { update(text, color: hex) } label: {
                            Circle()
                                .fill(textColor(hex))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Circle().stroke(
                                        model.selectedAnnotation?.text?.colorHex == hex ?
                                            WatakeColor.brand.primary : WatakeColor.border.strong,
                                        lineWidth: 2
                                    )
                                }
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose \(DocumentEditorPalette.colorName(for: hex).lowercased()) text color")
                    }
                }
            }
        }

        private var layerOrder: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Layer position").watakeType(.bodyEmphasis)
                HStack(spacing: WatakeSpacing.sm) {
                    Button { model.sendBackward() } label: {
                        Label("Move backward", systemImage: "square.2.layers.3d.bottom.filled")
                    }
                    Button { model.bringForward() } label: {
                        Label("Bring forward", systemImage: "square.2.layers.3d.top.filled")
                    }
                }
                .buttonStyle(.bordered)
            }
        }

        private func displaySize(_ fallback: AnnotationText) -> Int {
            Int((model.selectedAnnotation?.text?.fontSize ?? fallback.fontSize) * 1000)
        }

        private func update(
            _ _: AnnotationText,
            bold: Bool? = nil,
            italic: Bool? = nil,
            fontName: String? = nil,
            size: Double? = nil,
            color: String? = nil
        ) {
            guard let latest = model.selectedAnnotation?.text else { return }
            model.updateSelectedText(AnnotationText(
                text: latest.text,
                fontName: fontName ?? latest.fontName,
                fontSize: size ?? latest.fontSize,
                colorHex: color ?? latest.colorHex,
                alignment: latest.alignment,
                isBold: bold ?? latest.isBold,
                isItalic: italic ?? latest.isItalic,
                isUnderlined: latest.isUnderlined
            ))
        }

        private func textColor(_ hex: String) -> Color {
            guard hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return WatakeColor.text.primary }
            return Color(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        }
    }
#endif
