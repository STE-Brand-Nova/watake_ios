#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UIKit
    import WatakeDomain

    /// Full-screen text-layer editor. It displays the immutable document image
    /// as-is on a neutral surface and previews only the in-memory draft; this
    /// view intentionally has no Apply, Export, or persistence operation.
    public struct WatermarkEditorView: View {
        @Bindable private var model: WatermarkEditorModel
        private let sourceImageData: Data
        private let onDone: () -> Void

        public init(model: WatermarkEditorModel, sourceImageData: Data, onDone: @escaping () -> Void) {
            self.model = model
            self.sourceImageData = sourceImageData
            self.onDone = onDone
        }

        public var body: some View {
            GeometryReader { proxy in
                if WatermarkEditorLayout.usesTwoPanes(for: proxy.size.width) {
                    twoPaneLayout(availableWidth: proxy.size.width)
                } else {
                    compactLayout
                }
            }
            .background(WatakeColor.surface.base)
            .navigationTitle("Watermark")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { model.cancelPreviewWork() }
        }

        private var compactLayout: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: WatakeSpacing.lg) {
                    preview
                        .frame(minHeight: WatermarkEditorLayout.compactPreviewMinimumHeight)
                    WatermarkInspector(model: model)
                }
                .padding(WatakeSpacing.md)
            }
            .safeAreaInset(edge: .bottom) {
                doneButton
                    .padding(.horizontal, WatakeSpacing.md)
                    .padding(.vertical, WatakeSpacing.xs)
                    .background(WatakeColor.surface.base)
            }
        }

        private func twoPaneLayout(availableWidth: CGFloat) -> some View {
            HStack(spacing: 0) {
                preview
                    .frame(minWidth: WatermarkEditorLayout.previewMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
                    .padding(WatakeSpacing.xl)
                Divider()
                VStack(spacing: 0) {
                    ScrollView {
                        WatermarkInspector(model: model)
                            .padding(WatakeSpacing.md)
                    }
                    Divider()
                    doneButton
                        .padding(WatakeSpacing.md)
                }
                .frame(width: WatermarkEditorLayout.inspectorWidth(for: availableWidth))
                .background(WatakeColor.surface.raised)
            }
        }

        @ViewBuilder
        private var preview: some View {
            if let image = UIImage(data: sourceImageData) {
                WatermarkPreviewCanvas(sourceImage: image, preview: model.preview)
            } else {
                WatakeEmptyState(
                    systemImage: "doc.questionmark",
                    title: "Preview unavailable.",
                    message: "This page couldn't be displayed."
                )
            }
        }

        private var doneButton: some View {
            WatakeButton("Done", variant: .primary, accessibilityIdentifier: "watermarkEditor.done") {
                onDone()
            }
            .accessibilityHint("Closes the editor and discards this working draft")
        }
    }

    /// At 800pt the specified 480pt preview and 320pt inspector can coexist.
    /// Narrower containers remain compact to avoid horizontal overflow.
    public enum WatermarkEditorLayout {
        public static let previewMinimumWidth: CGFloat = 480
        public static let inspectorMinimumWidth: CGFloat = 320
        public static let inspectorMaximumWidth: CGFloat = 380
        public static let compactPreviewMinimumHeight: CGFloat = 320

        public static func usesTwoPanes(for width: CGFloat) -> Bool {
            width >= previewMinimumWidth + inspectorMinimumWidth
        }

        public static func inspectorWidth(for availableWidth: CGFloat) -> CGFloat {
            let preferred = availableWidth * 0.30
            return min(max(preferred, inspectorMinimumWidth), inspectorMaximumWidth)
        }
    }

    private struct WatermarkInspector: View {
        @Bindable var model: WatermarkEditorModel

        var body: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.md) {
                WatermarkEditorSegmentedControl(selection: $model.selectedTab)
                inspectorContent
            }
        }

        @ViewBuilder
        private var inspectorContent: some View {
            switch model.selectedTab {
            case .heading:
                WatermarkTextLayerInspector(kind: .heading, model: model)
            case .body:
                WatermarkTextLayerInspector(kind: .body, model: model)
            case .caption:
                WatermarkTextLayerInspector(kind: .caption, model: model)
            case .image:
                WatermarkImageLayerInspector(model: model)
            case .global:
                WatermarkUnavailableInspector(
                    title: "Global controls",
                    message: "Shared placement and automatic watermark controls arrive later."
                )
            }
        }
    }

    private struct WatermarkEditorSegmentedControl: View {
        @Binding var selection: WatermarkEditorTab

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WatakeSpacing.xxs) {
                    ForEach(WatermarkEditorTab.allCases) { tab in
                        Button {
                            selection = tab
                        } label: {
                            Text(tab.title)
                                .watakeType(.caption)
                                .foregroundStyle(selection == tab ? WatakeColor.text.onPrimary : WatakeColor.text.primary)
                                .frame(minWidth: 44, minHeight: 44)
                                .padding(.horizontal, WatakeSpacing.xs)
                                .background(selection == tab ? WatakeColor.brand.primary : WatakeColor.surface.sunken)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(tab.title) layer")
                        .accessibilityValue(selection == tab ? "Selected" : "Not selected")
                    }
                }
                .padding(WatakeSpacing.xxs)
            }
            .background(WatakeColor.surface.sunken)
            .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous))
            .accessibilityLabel("Watermark layer")
        }
    }

    private struct WatermarkTextLayerInspector: View {
        let kind: WatermarkTextLayerKind
        @Bindable var model: WatermarkEditorModel

        private var layer: EditableWatermarkTextLayer {
            model.layer(for: kind)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.lg) {
                Toggle(isOn: enabledBinding) {
                    Text("Enable \(kind.title)")
                        .watakeType(.bodyEmphasis)
                        .foregroundStyle(WatakeColor.text.primary)
                }
                .tint(WatakeColor.brand.primary)
                .frame(minHeight: 44)
                .accessibilityHint("Includes this layer in the preview when it has text")

                textEditor
                fontPicker
                sizePicker
                colorControls
                rotationControls
                opacityControls
            }
        }

        private var textEditor: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Text")
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                TextEditor(text: textBinding)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .padding(WatakeSpacing.xs)
                    .background(WatakeColor.surface.sunken)
                    .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous)
                            .strokeBorder(WatakeColor.border.subtle, lineWidth: 1)
                    }
                    .accessibilityLabel("\(kind.title) text")
                    .accessibilityHint("Empty text is not shown in the preview")
            }
        }

        private var fontPicker: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Font")
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                Picker("Font", selection: fontBinding) {
                    ForEach(WatermarkFontCatalog.supportedFontNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .tint(WatakeColor.brand.primary)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityLabel("\(kind.title) font")
            }
        }

        private var sizePicker: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Size")
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                Picker("Size", selection: sizeBinding) {
                    Text("Small").tag(WatermarkSizePreset.small)
                    Text("Medium").tag(WatermarkSizePreset.medium)
                    Text("Large").tag(WatermarkSizePreset.large)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
                .accessibilityLabel("\(kind.title) size")
            }
        }

        private var colorControls: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Color")
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                Picker("Color", selection: semanticColorBinding) {
                    Text("Custom").tag(nil as WatermarkSemanticColor?)
                    ForEach(WatermarkSemanticColor.allCases) { color in
                        Text(color.title).tag(Optional(color))
                    }
                }
                .pickerStyle(.menu)
                .tint(WatakeColor.brand.primary)
                .frame(minHeight: 44, alignment: .leading)
                TextField("#RRGGBB", text: colorInputBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .watermarkInputSurface()
                    .onSubmit { model.commitColorInput(for: kind) }
                    .accessibilityLabel("\(kind.title) color hex")
                    .accessibilityValue(model.colorInput(for: kind))
                    .accessibilityHint("Enter a six-digit hex color. Invalid values keep the last safe preview color.")
            }
        }

        private var rotationControls: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Rotation")
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                HStack(spacing: WatakeSpacing.sm) {
                    Slider(value: rotationBinding, in: -180 ... 180, step: 1)
                        .tint(WatakeColor.brand.primary)
                        .frame(minHeight: 44)
                        .accessibilityLabel("\(kind.title) rotation slider")
                    TextField("Degrees", value: rotationBinding, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numbersAndPunctuation)
                        .watermarkInputSurface()
                        .frame(width: 88)
                        .accessibilityLabel("\(kind.title) rotation in degrees")
                        .accessibilityValue("\(Int(layer.rotation)) degrees")
                }
                Text("-180 to 180 degrees")
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.secondary)
            }
        }

        private var opacityControls: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Opacity")
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                HStack(spacing: WatakeSpacing.sm) {
                    Slider(value: opacityBinding, in: 0 ... 1, step: 0.01)
                        .tint(WatakeColor.brand.primary)
                        .frame(minHeight: 44)
                        .accessibilityLabel("\(kind.title) opacity slider")
                    TextField("Opacity", value: opacityBinding, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .watermarkInputSurface()
                        .frame(width: 88)
                        .accessibilityLabel("\(kind.title) opacity")
                        .accessibilityValue("\(Int(layer.opacity * 100)) percent")
                }
                Text("0 to 1")
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.secondary)
            }
        }

        private var enabledBinding: Binding<Bool> {
            Binding(get: { layer.enabled }, set: { model.setEnabled($0, for: kind) })
        }

        private var textBinding: Binding<String> {
            Binding(get: { layer.text }, set: { model.setText($0, for: kind) })
        }

        private var fontBinding: Binding<String> {
            Binding(get: { layer.fontName }, set: { model.setFontName($0, for: kind) })
        }

        private var sizeBinding: Binding<WatermarkSizePreset> {
            Binding(get: { layer.sizePreset }, set: { model.setSizePreset($0, for: kind) })
        }

        private var colorInputBinding: Binding<String> {
            Binding(get: { model.colorInput(for: kind) }, set: { model.setColorInput($0, for: kind) })
        }

        private var semanticColorBinding: Binding<WatermarkSemanticColor?> {
            Binding(
                get: { WatermarkSemanticColor.allCases.first { $0.hex == layer.colorHex } },
                set: { color in
                    guard let color else { return }
                    model.setSemanticColor(color, for: kind)
                }
            )
        }

        private var rotationBinding: Binding<Double> {
            Binding(get: { layer.rotation }, set: { model.setRotation($0, for: kind) })
        }

        private var opacityBinding: Binding<Double> {
            Binding(get: { layer.opacity }, set: { model.setOpacity($0, for: kind) })
        }
    }

    private struct WatermarkUnavailableInspector: View {
        let title: String
        let message: String

        var body: some View {
            WatakeCard(surface: .sunken) {
                VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                    Image(systemName: "clock")
                        .foregroundStyle(WatakeColor.text.secondary)
                        .accessibilityHidden(true)
                    Text(title)
                        .watakeType(.bodyEmphasis)
                        .foregroundStyle(WatakeColor.text.primary)
                    Text(message)
                        .watakeType(.body)
                        .foregroundStyle(WatakeColor.text.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityValue("Unavailable")
        }
    }

    private struct WatermarkPreviewCanvas: View {
        let sourceImage: UIImage
        let preview: WatermarkEditorPreview

        var body: some View {
            GeometryReader { proxy in
                let pageSize = fittedPageSize(in: proxy.size)
                ZStack {
                    Image(uiImage: sourceImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: pageSize.width, height: pageSize.height)
                    WatermarkPreviewCompositionView(preview: preview)
                        .frame(width: pageSize.width, height: pageSize.height)
                        .clipShape(Rectangle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(WatakeColor.surface.sunken)
            .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WatakeRadius.lg, style: .continuous)
                    .strokeBorder(WatakeColor.border.subtle, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Live document preview")
            .accessibilityValue(previewAccessibilityValue)
        }

        private var previewAccessibilityValue: String {
            let textCount = preview.textLayers.count
            let textDescription = "\(textCount) visible text layer\(textCount == 1 ? "" : "s")"
            return preview.hasRenderableImage ? "\(textDescription), 1 visible image layer" : textDescription
        }

        private func fittedPageSize(in available: CGSize) -> CGSize {
            let imageSize = sourceImage.size
            guard imageSize.width > 0, imageSize.height > 0 else { return available }
            let scale = min(available.width / imageSize.width, available.height / imageSize.height)
            return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        }
    }

    private struct WatermarkTextStack: View {
        let layers: [WatermarkEditorPreviewLayer]

        var body: some View {
            VStack(spacing: WatakeSpacing.xs) {
                ForEach(layers) { previewLayer in
                    Text(previewLayer.layer.text)
                        .font(font(for: previewLayer.layer))
                        .foregroundStyle(Color(hex: previewLayer.layer.colorHex))
                        .multilineTextAlignment(.center)
                        .rotationEffect(.degrees(previewLayer.layer.rotation))
                        .opacity(previewLayer.layer.opacity)
                        .accessibilityHidden(true)
                }
            }
            .padding(WatakeSpacing.md)
        }

        private func font(for layer: EditableWatermarkTextLayer) -> Font {
            let size: CGFloat = switch layer.sizePreset {
            case .small: 16
            case .medium: 24
            case .large: 32
            }
            return .custom(layer.fontName, size: size)
        }
    }

    private struct WatermarkPreviewCompositionView: View {
        let preview: WatermarkEditorPreview

        var body: some View {
            switch preview.composition {
            case .textOnly:
                text
            case .imageOnly:
                image
            case .imageBehindText:
                ZStack { image
                    text
                }
            case .imageAboveText:
                ZStack { text
                    image
                }
            case .imageLeftOfText:
                HStack(spacing: WatakeSpacing.sm) { image
                    text
                }
                .padding(WatakeSpacing.md)
            case .imageRightOfText:
                HStack(spacing: WatakeSpacing.sm) { text
                    image
                }
                .padding(WatakeSpacing.md)
            }
        }

        private var text: some View {
            WatermarkTextStack(layers: preview.textLayers)
        }

        @ViewBuilder
        private var image: some View {
            if let imageData = preview.imageData, let image = UIImage(data: imageData) {
                WatermarkPreviewImage(image: image, layer: preview.imageLayer)
            }
        }
    }

    private struct WatermarkPreviewImage: View {
        let image: UIImage
        let layer: EditableWatermarkImageLayer

        var body: some View {
            GeometryReader { proxy in
                let base = min(proxy.size.width, proxy.size.height) * 0.28
                if let tintHex = layer.tintHex {
                    Image(uiImage: image)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(Color(hex: tintHex))
                        .imageLayout(base: base, layer: layer)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .imageLayout(base: base, layer: layer)
                }
            }
            .accessibilityHidden(true)
        }
    }

    extension View {
        fileprivate func imageLayout(base: CGFloat, layer: EditableWatermarkImageLayer) -> some View {
            aspectRatio(contentMode: .fit)
                .frame(width: base * layer.scale, height: base * layer.scale)
                .rotationEffect(.degrees(layer.rotation))
                .opacity(layer.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        func watermarkInputSurface() -> some View {
            padding(.horizontal, WatakeSpacing.sm)
                .frame(minHeight: 44)
                .background(WatakeColor.surface.sunken)
                .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous)
                        .strokeBorder(WatakeColor.border.subtle, lineWidth: 1)
                }
        }
    }

    extension Color {
        fileprivate init(hex: String) {
            let digits = hex.dropFirst(hex.hasPrefix("#") ? 1 : 0)
            let value = UInt64(digits, radix: 16) ?? 0
            self.init(
                .sRGB,
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                opacity: 1
            )
        }
    }
#endif
