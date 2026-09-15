#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers
    import WatakeDomain

    struct ImageStyleSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: DocumentEditorModel
        let replaceImage: () -> Void

        var body: some View {
            NavigationStack {
                List {
                    Section("Image") {
                        Button(action: replaceImage) {
                            Label("Replace image", systemImage: "photo.badge.arrow.down")
                        }
                        Button {
                            model.rotateSelectedImage(by: 90)
                        } label: {
                            Label("Rotate 90°", systemImage: "rotate.right")
                        }
                        Button {
                            model.resetSelectedImageRotation()
                        } label: {
                            Label("Reset rotation", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(abs(model.selectedAnnotation?.transform.rotation ?? 0) < 0.001)
                    }

                    Section("Flip") {
                        Button {
                            model.flipSelectedImageHorizontally()
                        } label: {
                            Label(
                                "Flip horizontal",
                                systemImage: model.selectedAnnotation?.isFlippedHorizontally == true
                                    ? "checkmark.rectangle" : "arrow.left.and.right.righttriangle.left.righttriangle.right"
                            )
                        }
                        Button {
                            model.flipSelectedImageVertically()
                        } label: {
                            Label(
                                "Flip vertical",
                                systemImage: model.selectedAnnotation?.isFlippedVertically == true
                                    ? "checkmark.rectangle" : "arrow.up.and.down.righttriangle.up.righttriangle.down"
                            )
                        }
                    }

                    Section("Layer") {
                        Button { model.bringForward() } label: {
                            Label("Bring forward", systemImage: "square.2.layers.3d.top.filled")
                        }
                        Button { model.sendBackward() } label: {
                            Label("Send backward", systemImage: "square.2.layers.3d.bottom.filled")
                        }
                    }
                }
                .navigationTitle("Image")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    struct ImageContextToolbar: View {
        let rotation: Double
        let delete: () -> Void
        let duplicate: () -> Void
        let showMore: () -> Void

        var body: some View {
            HStack(spacing: WatakeSpacing.xxs) {
                actionButton(icon: "trash", label: "Delete image", role: .destructive, action: delete)
                actionButton(icon: "doc.on.doc", label: "Duplicate image", action: duplicate)
                actionButton(icon: "ellipsis", label: "More image options", action: showMore)
            }
            .padding(WatakeSpacing.xxs)
            .background(WatakeColor.surface.raised)
            .clipShape(Capsule())
            .shadow(color: WatakeColor.text.primary.opacity(0.18), radius: 8, y: 3)
            .rotationEffect(.degrees(-rotation))
        }

        private func actionButton(
            icon: String,
            label: String,
            role: ButtonRole? = nil,
            action: @escaping () -> Void
        ) -> some View {
            Button(role: role, action: action) {
                Image(systemName: icon)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(role == .destructive ? WatakeColor.status.danger : WatakeColor.text.primary)
            .accessibilityLabel(label)
        }
    }

    struct ImageSelectionHandle: View {
        let label: String
        let corner: ImageResizeCorner
        let resize: (Double) -> Void

        var body: some View {
            ZStack {
                Circle()
                    .fill(WatakeColor.surface.raised)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(WatakeColor.brand.primary, lineWidth: 2))
                    .offset(
                        x: CGFloat(corner.horizontalSign) * 13,
                        y: CGFloat(corner.verticalSign) * 13
                    )
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
            .accessibilityHint("Swipe up to enlarge or down to shrink.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: resize(1.1)
                case .decrement: resize(0.9)
                @unknown default: break
                }
            }
        }
    }

    struct ImageRotationHandle: View {
        let rotation: Double

        var body: some View {
            Image(systemName: "arrow.clockwise")
                .font(.caption.weight(.bold))
                .foregroundStyle(WatakeColor.brand.primary)
                .frame(width: 28, height: 28)
                .background(WatakeColor.surface.raised)
                .clipShape(Circle())
                .overlay(Circle().stroke(WatakeColor.brand.primary, lineWidth: 2))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(-rotation))
                .accessibilityLabel("Rotate image")
        }
    }

    struct ImagePlacementOverlay: View {
        @Bindable var model: DocumentEditorModel
        let pageSize: CGSize
        @GestureState private var preview: AnnotationTransform?

        var body: some View {
            if let pending = model.pendingImagePlacement {
                ZStack {
                    if let transform = preview {
                        EditableAnnotationImage(id: pending.id, data: pending.data, targetSize: pageSize)
                            .frame(
                                width: transform.width * pageSize.width,
                                height: transform.height * pageSize.height
                            )
                            .overlay {
                                Rectangle()
                                    .stroke(
                                        WatakeColor.brand.primary,
                                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                                    )
                            }
                            .position(
                                x: transform.centerX * pageSize.width,
                                y: transform.centerY * pageSize.height
                            )
                            .opacity(0.78)
                            .allowsHitTesting(false)
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(placementGesture(pending))
                }
                .accessibilityLabel("Place image")
                .accessibilityHint("Tap the page for a default size, or drag to choose the image size.")
            }
        }

        private func placementGesture(_ pending: PendingImagePlacement) -> some Gesture {
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace)
            )
            .updating($preview) { value, preview, _ in
                preview = DocumentImageInteraction.placement(
                    from: value.startLocation,
                    to: value.location,
                    imageAspectRatio: pending.aspectRatio,
                    pageSize: pageSize
                )
            }
            .onEnded { value in
                let transform = DocumentImageInteraction.placement(
                    from: value.startLocation,
                    to: value.location,
                    imageAspectRatio: pending.aspectRatio,
                    pageSize: pageSize
                )
                Task { _ = await model.placePendingImage(transform: transform) }
            }
        }
    }

    struct CameraImagePicker: UIViewControllerRepresentable {
        let onCancel: () -> Void
        let onCapture: (UIImage) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onCancel: onCancel, onCapture: onCapture)
        }

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_: UIImagePickerController, context _: Context) {}

        final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
            let onCancel: () -> Void
            let onCapture: (UIImage) -> Void

            init(onCancel: @escaping () -> Void, onCapture: @escaping (UIImage) -> Void) {
                self.onCancel = onCancel
                self.onCapture = onCapture
            }

            func imagePickerControllerDidCancel(_: UIImagePickerController) {
                onCancel()
            }

            func imagePickerController(
                _: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                guard let image = info[.originalImage] as? UIImage else {
                    onCancel()
                    return
                }
                onCapture(image)
            }
        }
    }

    struct DocumentImageFilePicker: UIViewControllerRepresentable {
        let onCancel: () -> Void
        let onPick: (URL) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onCancel: onCancel, onPick: onPick)
        }

        func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.png, .jpeg, .heic],
                asCopy: true
            )
            picker.allowsMultipleSelection = false
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}

        final class Coordinator: NSObject, UIDocumentPickerDelegate {
            let onCancel: () -> Void
            let onPick: (URL) -> Void

            init(onCancel: @escaping () -> Void, onPick: @escaping (URL) -> Void) {
                self.onCancel = onCancel
                self.onPick = onPick
            }

            func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
                onCancel()
            }

            func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                guard let url = urls.first else {
                    onCancel()
                    return
                }
                onPick(url)
            }
        }
    }
#endif
