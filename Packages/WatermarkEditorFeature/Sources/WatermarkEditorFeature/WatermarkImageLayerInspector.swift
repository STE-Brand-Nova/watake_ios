#if canImport(UIKit)
    import DesignSystem
    import Foundation
    import PhotosUI
    import SwiftUI
    import UIKit
    import WatakeDomain

    struct WatermarkImageLayerInspector: View {
        @Bindable var model: WatermarkEditorModel
        @State private var pickerItem: PhotosPickerItem?
        @State private var pickerTransfer = WatermarkPickerTransferCoordinator()

        private var layer: EditableWatermarkImageLayer {
            model.imageLayer()
        }

        private var hasImage: Bool {
            model.imageImportState == .loaded
        }

        var body: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.lg) {
                imageSelection
                if hasImage {
                    Toggle(isOn: enabledBinding) {
                        Text("Enable image")
                            .watakeType(.bodyEmphasis)
                            .foregroundStyle(WatakeColor.text.primary)
                    }
                    .tint(WatakeColor.brand.primary)
                    .frame(minHeight: 44)
                    .accessibilityHint("Includes the selected image in the preview")

                    scaleControls
                    placementPicker
                    tintControls
                    rotationControls
                    opacityControls
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                startPickerTransfer(for: newItem)
            }
            .onDisappear { pickerTransfer.invalidate() }
        }

        @ViewBuilder
        private var imageSelection: some View {
            if hasImage {
                VStack(alignment: .leading, spacing: WatakeSpacing.sm) {
                    if let image = model.preview.imageData.flatMap(UIImage.init(data:)) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .frame(maxWidth: .infinity)
                            .padding(WatakeSpacing.sm)
                            .background(WatakeColor.surface.sunken)
                            .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: WatakeSpacing.sm) {
                        photoPicker(label: "Replace image")
                        Button("Remove", role: .destructive) {
                            pickerTransfer.invalidate()
                            pickerItem = nil
                            model.removeImage()
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Remove selected image")
                    }
                }
            } else {
                WatakeCard(surface: .sunken) {
                    VStack(alignment: .leading, spacing: WatakeSpacing.sm) {
                        Image(systemName: "photo")
                            .foregroundStyle(WatakeColor.text.secondary)
                            .accessibilityHidden(true)
                        Text("Image layer")
                            .watakeType(.bodyEmphasis)
                            .foregroundStyle(WatakeColor.text.primary)
                        Text("Choose a PNG or JPEG image for this in-memory preview.")
                            .watakeType(.body)
                            .foregroundStyle(WatakeColor.text.secondary)
                        photoPicker(label: "Choose image")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }

            if let error = model.imageImportError {
                Text(error.message)
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.secondary)
                    .accessibilityLabel("Image selection error")
                    .accessibilityValue(error.message)
            }
        }

        private func photoPicker(label: String) -> some View {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(label, systemImage: "photo.on.rectangle")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatakeColor.brand.primary)
            .accessibilityLabel(label)
            .accessibilityHint("Opens your photo library")
        }

        private func startPickerTransfer(for item: PhotosPickerItem?) {
            let token = pickerTransfer.begin()
            guard let item else { return }
            let transfer = pickerTransfer
            let model = model
            let pickerSelection = $pickerItem
            let task = Task { @MainActor in
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        guard transfer.isCurrent(token), !Task.isCancelled else { return }
                        model.rejectImageImport()
                        pickerSelection.wrappedValue = nil
                        return
                    }
                    guard transfer.isCurrent(token), !Task.isCancelled else { return }
                    model.importImage(data: data)
                    pickerSelection.wrappedValue = nil
                } catch is CancellationError {
                    return
                } catch {
                    guard transfer.isCurrent(token), !Task.isCancelled else { return }
                    model.rejectImageImport()
                    pickerSelection.wrappedValue = nil
                }
            }
            pickerTransfer.store(task)
        }

        private var scaleControls: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Scale")
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                HStack(spacing: WatakeSpacing.sm) {
                    Slider(value: scaleBinding, in: 0.1 ... 3, step: 0.1)
                        .tint(WatakeColor.brand.primary)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Image scale slider")
                    TextField("Scale", value: scaleBinding, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .watermarkInputSurface()
                        .frame(width: 88)
                        .accessibilityLabel("Image scale")
                        .accessibilityValue(String(format: "%.1f", layer.scale))
                }
                Text("0.1 to 3")
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.secondary)
            }
        }

        private var placementPicker: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Placement")
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                Picker("Image placement", selection: placementBinding) {
                    ForEach(WatermarkImagePlacement.allCases, id: \.self) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.menu)
                .tint(WatakeColor.brand.primary)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityLabel("Image placement")
                .accessibilityValue(layer.placement.title)
            }
        }

        private var tintControls: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Toggle("Tint image", isOn: tintEnabledBinding)
                    .tint(WatakeColor.brand.primary)
                    .frame(minHeight: 44)
                if layer.tintHex != nil {
                    Picker("Tint", selection: semanticTintBinding) {
                        Text("Custom").tag(nil as WatermarkSemanticColor?)
                        ForEach(WatermarkSemanticColor.allCases) { color in
                            Text(color.title).tag(Optional(color))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(WatakeColor.brand.primary)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityLabel("Image tint color")
                    TextField("#RRGGBB", text: tintInputBinding)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .watermarkInputSurface()
                        .onSubmit {
                            model.commitImageTintInput()
                        }
                        .accessibilityLabel("Image tint hex")
                        .accessibilityValue(model.tintInput())
                        .accessibilityHint("Enter a six-digit hex color. Invalid values keep the last safe preview color.")
                }
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
                        .accessibilityLabel("Image rotation slider")
                    TextField("Degrees", value: rotationBinding, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numbersAndPunctuation)
                        .watermarkInputSurface()
                        .frame(width: 88)
                        .accessibilityLabel("Image rotation in degrees")
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
                        .accessibilityLabel("Image opacity slider")
                    TextField("Opacity", value: opacityBinding, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .watermarkInputSurface()
                        .frame(width: 88)
                        .accessibilityLabel("Image opacity")
                        .accessibilityValue("\(Int(layer.opacity * 100)) percent")
                }
                Text("0 to 1")
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.secondary)
            }
        }

        private var enabledBinding: Binding<Bool> {
            Binding(get: { layer.enabled }, set: { model.setImageEnabled($0) })
        }

        private var scaleBinding: Binding<Double> {
            Binding(get: { layer.scale }, set: { model.setImageScale($0) })
        }

        private var placementBinding: Binding<WatermarkImagePlacement> {
            Binding(get: { layer.placement }, set: { model.setImagePlacement($0) })
        }

        private var tintEnabledBinding: Binding<Bool> {
            Binding(get: { layer.tintHex != nil }, set: { model.setImageTintEnabled($0) })
        }

        private var tintInputBinding: Binding<String> {
            Binding(get: { model.tintInput() }, set: { model.setImageTintInput($0) })
        }

        private var semanticTintBinding: Binding<WatermarkSemanticColor?> {
            Binding(
                get: { WatermarkSemanticColor.allCases.first { $0.hex == layer.tintHex } },
                set: { color in
                    guard let color else { return }
                    model.setImageSemanticTint(color)
                }
            )
        }

        private var rotationBinding: Binding<Double> {
            Binding(get: { layer.rotation }, set: { model.setImageRotation($0) })
        }

        private var opacityBinding: Binding<Double> {
            Binding(get: { layer.opacity }, set: { model.setImageOpacity($0) })
        }
    }

    extension WatermarkImagePlacement {
        fileprivate static var allCases: [Self] {
            [.behindText, .aboveText, .leftOfText, .rightOfText]
        }

        fileprivate var title: String {
            switch self {
            case .behindText: "Behind text"
            case .aboveText: "Above text"
            case .leftOfText: "Left of text"
            case .rightOfText: "Right of text"
            }
        }
    }

    @MainActor
    private final class WatermarkPickerTransferCoordinator {
        private var token = 0
        private var task: Task<Void, Never>?

        func begin() -> Int {
            task?.cancel()
            token &+= 1
            return token
        }

        func store(_ task: Task<Void, Never>) {
            self.task = task
        }

        func isCurrent(_ candidate: Int) -> Bool {
            candidate == token
        }

        func invalidate() {
            _ = begin()
        }
    }
#endif
