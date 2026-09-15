#if canImport(UIKit)
    import ImageIO
    import PhotosUI
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers

    enum ImageImportPurpose: Equatable {
        case placement
        case replacement
    }

    extension View {
        func documentImageImporter(
            model: DocumentEditorModel,
            request: Binding<ImageImportPurpose?>
        ) -> some View {
            modifier(DocumentImageImportModifier(model: model, request: request))
        }
    }

    private struct DocumentImageImportModifier: ViewModifier {
        @Bindable var model: DocumentEditorModel
        @Binding var request: ImageImportPurpose?
        @State private var showsSourceChooser = false
        @State private var showsPhotoPicker = false
        @State private var showsFileImporter = false
        @State private var showsCamera = false
        @State private var photoItem: PhotosPickerItem?
        @State private var isReceivingPhoto = false

        func body(content: Content) -> some View {
            cameraPresenter(filePresenter(photoPresenter(sourcePresenter(content))))
        }

        private func sourcePresenter(_ content: some View) -> some View {
            content
                .onChange(of: request) { _, purpose in
                    guard let purpose else { return }
                    if purpose == .placement {
                        model.activateTool(.image)
                    }
                    showsSourceChooser = true
                }
                .confirmationDialog(
                    request == .placement ? "Add image" : "Replace image",
                    isPresented: $showsSourceChooser,
                    titleVisibility: .visible
                ) {
                    Button("Photos") { showsPhotoPicker = true }
                    Button("Files") { showsFileImporter = true }
                    Button("Camera") { showsCamera = true }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    Button("Cancel", role: .cancel) { cancelImport() }
                } message: {
                    Text("Choose where the image comes from.")
                }
        }

        private func photoPresenter(_ content: some View) -> some View {
            content
                .photosPicker(isPresented: $showsPhotoPicker, selection: $photoItem, matching: .images)
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    isReceivingPhoto = true
                    Task {
                        defer {
                            photoItem = nil
                            isReceivingPhoto = false
                        }
                        guard let data = try? await item.loadTransferable(type: Data.self),
                              let payload = await ImageImportDataLoader.inspect(data: data) else {
                            cancelImport()
                            return
                        }
                        let type = item.supportedContentTypes.first
                        await receive(
                            data: data,
                            mediaType: type?.preferredMIMEType ?? "application/octet-stream",
                            fileExtension: type?.preferredFilenameExtension ?? "img",
                            aspectRatio: payload.aspectRatio
                        )
                    }
                }
                .onChange(of: showsPhotoPicker) { _, isPresented in
                    guard !isPresented else { return }
                    if photoItem == nil, !isReceivingPhoto {
                        cancelImport()
                    }
                }
        }

        private func filePresenter(_ content: some View) -> some View {
            content
                .sheet(isPresented: $showsFileImporter) {
                    DocumentImageFilePicker(
                        onCancel: {
                            showsFileImporter = false
                            cancelImport()
                        },
                        onPick: receiveFile
                    )
                }
        }

        private func cameraPresenter(_ content: some View) -> some View {
            content
                .fullScreenCover(isPresented: $showsCamera) {
                    CameraImagePicker(
                        onCancel: {
                            showsCamera = false
                            cancelImport()
                        },
                        onCapture: { image in
                            showsCamera = false
                            guard let data = image.jpegData(compressionQuality: 0.95) else {
                                cancelImport()
                                return
                            }
                            Task {
                                await receive(
                                    data: data,
                                    mediaType: "image/jpeg",
                                    fileExtension: "jpg",
                                    aspectRatio: Double(image.size.width / max(image.size.height, 1))
                                )
                            }
                        }
                    )
                    .ignoresSafeArea()
                }
        }

        private func receiveFile(_ url: URL) {
            showsFileImporter = false
            let accessed = url.startAccessingSecurityScopedResource()
            let type = UTType(filenameExtension: url.pathExtension)
            Task {
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard let payload = await ImageImportDataLoader.load(url: url) else {
                    cancelImport()
                    return
                }
                await receive(
                    data: payload.data,
                    mediaType: type?.preferredMIMEType ?? "application/octet-stream",
                    fileExtension: url.pathExtension,
                    aspectRatio: payload.aspectRatio
                )
            }
        }

        @MainActor
        private func receive(data: Data, mediaType: String, fileExtension: String, aspectRatio: Double) async {
            guard let purpose = request else { return }
            switch purpose {
            case .placement:
                _ = model.prepareImagePlacement(
                    data: data,
                    mediaType: mediaType,
                    fileExtension: fileExtension,
                    aspectRatio: aspectRatio
                )
            case .replacement:
                _ = await model.replaceSelectedImage(
                    data: data,
                    mediaType: mediaType,
                    fileExtension: fileExtension
                )
            }
            request = nil
        }

        private func cancelImport() {
            if request == .placement, model.pendingImagePlacement == nil {
                model.cancelImagePlacement()
            }
            request = nil
        }
    }

    private struct ImportedImageData: Sendable {
        let data: Data
        let aspectRatio: Double
    }

    private enum ImageImportDataLoader {
        static func load(url: URL) async -> ImportedImageData? {
            await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return inspected(data: data)
            }.value
        }

        static func inspect(data: Data) async -> ImportedImageData? {
            await Task.detached(priority: .userInitiated) {
                inspected(data: data)
            }.value
        }

        private static func inspected(data: Data) -> ImportedImageData? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
                  width > 0, height > 0 else { return nil }
            return ImportedImageData(data: data, aspectRatio: width / height)
        }
    }
#endif
