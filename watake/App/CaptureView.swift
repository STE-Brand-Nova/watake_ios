import AVFoundation
import CaptureServices
import DesignSystem
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WatakeDomain

struct CaptureView: View {
    @Bindable var store: LibraryStore
    @State private var mode: Mode = .scanner
    @State private var showScanner = false
    @State private var showRawCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pages: [ReviewPage] = []
    @State private var grouping: GalleryGrouping = .oneDocument
    @State private var isChoosingGrouping = false
    @State private var isSaving = false
    @State private var showDestination = false
    @State private var captureError: String?

    var body: some View {
        VStack(spacing: WatakeSpacing.xl) {
            Picker("Capture mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, WatakeSpacing.md)

            if pages.isEmpty {
                sourcePicker
            } else {
                CaptureReview(pages: $pages, retake: retake, save: { showDestination = true })
            }
        }
        .background(WatakeColor.surface.base)
        .navigationTitle("Capture")
        .watakeDocumentScanner(isPresented: $showScanner) { result in
            switch result {
            case .success(let scan): pages = scan.map { ReviewPage(source: $0.jpegData, rectified: $0.jpegData, detectionUncertain: false) }
            case .failure(.cancelled): break
            case .failure: captureError = "Scanner could not finish. Check camera access and try again."
            }
        }
        .sheet(isPresented: $showRawCamera) {
            RawCameraCapture { result in
                showRawCamera = false
                switch result {
                case .success(let data): pages = [ReviewPage(source: data, rectified: nil, detectionUncertain: false)]
                case .failure(.cancelled): break
                case .failure: captureError = "Camera is unavailable. Check camera access and try again."
                }
            }
        }
        .confirmationDialog("Save selected photos", isPresented: $isChoosingGrouping, titleVisibility: .visible) {
            Button("One multi-page document") { grouping = .oneDocument }
            Button("Separate documents") { grouping = .separateDocuments }
            Button("Cancel", role: .cancel) { pickerItems = [] }
        } message: { Text("Choose how selected images should be added to your archive.") }
        .sheet(isPresented: $showDestination) {
            SaveDestination(store: store, pages: pages, grouping: grouping, isSaving: $isSaving) {
                pages = CaptureSaveState.pagesAfterSave(pages, succeeded: true)
                showDestination = false
            }
        }
        .alert("Capture needs attention", isPresented: Binding(get: { captureError != nil }, set: {
            if !$0 {
                captureError = nil
            }
        })) {
            Button("OK") {}
        } message: { Text(captureError ?? "Try again.") }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await loadGallery(newItems) }
        }
    }

    private var sourcePicker: some View {
        VStack(spacing: WatakeSpacing.md) {
            Image(systemName: mode.symbol).font(.system(size: 56)).foregroundStyle(WatakeColor.brand.primary)
            Text(mode.description).watakeType(.body).foregroundStyle(WatakeColor.text.secondary).multilineTextAlignment(.center).padding(
                .horizontal,
                WatakeSpacing.xl
            )
            switch mode {
            case .raw:
                WatakeButton("Take photo") { showRawCamera = true }
            case .scanner:
                WatakeButton("Scan document") { showScanner = true }
            case .gallery:
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                    Label("Choose photos", systemImage: "photo.on.rectangle")
                }.buttonStyle(.watake(.primary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retake() {
        pages = []
        pickerItems = []
        mode = .scanner
    }

    private func loadGallery(_ items: [PhotosPickerItem]) async {
        var result: [ReviewPage] = []
        let rectifier = DocumentRectifier()
        for item in items {
            if Task.isCancelled {
                return
            }
            guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else { continue }
            let detection = await rectifier.detect(in: data)
            let rectified = detection.isDetectionConfident
                ? await rectifier.rectify(jpeg: data, quadrilateral: detection.quadrilateral)
                : nil
            let type = item.supportedContentTypes.first
            result.append(ReviewPage(
                source: data,
                sourceMediaType: type?.preferredMIMEType ?? "image/jpeg",
                sourceFileExtension: type?.preferredFilenameExtension ?? "jpg",
                rectified: rectified,
                detectionUncertain: !detection.isDetectionConfident
            ))
        }
        guard !result.isEmpty else { captureError = "No selected photos could be imported."
            return
        }
        pages = result
        isChoosingGrouping = true
    }
}

private enum Mode: String, CaseIterable, Identifiable {
    case raw, scanner, gallery
    var id: String {
        rawValue
    }

    var label: String {
        rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .raw: "camera"
        case .scanner: "viewfinder"
        case .gallery: "photo.on.rectangle"
        }
    }

    var description: String {
        switch self {
        case .raw: "Take an untouched one-page source photo."
        case .scanner: "Scan one or more pages with Apple document detection."
        case .gallery: "Import selected photos as one document or separate documents."
        }
    }
}

private struct ReviewPage: Identifiable, Equatable {
    let id = UUID()
    var source: Data
    var sourceMediaType = "image/jpeg"
    var sourceFileExtension = "jpg"
    var rectified: Data?
    var detectionUncertain: Bool
}

private struct CaptureReview: View {
    @Binding var pages: [ReviewPage]
    let retake: () -> Void
    let save: () -> Void
    @State private var selected = 0
    @State private var editingCrop = false
    var body: some View {
        VStack(spacing: WatakeSpacing.md) {
            if pages.indices.contains(selected), let image = UIImage(data: pages[selected].rectified ?? pages[selected].source) {
                Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Captured page \(selected + 1)")
                    .padding(.horizontal, WatakeSpacing.md)
            }
            if pages.indices.contains(selected), pages[selected].detectionUncertain {
                Label("Review crop before saving", systemImage: "exclamationmark.triangle").foregroundStyle(WatakeColor.status.warning)
            }
            ScrollView(.horizontal) {
                HStack {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, _ in
                        Button("Page \(index + 1)") { selected = index }.buttonStyle(.bordered)
                    }
                }
            }
            HStack {
                WatakeButton("Retake", variant: .secondary, action: retake)
                WatakeButton("Adjust corners", variant: .secondary) { editingCrop = true }.disabled(!pages.indices.contains(selected))
                WatakeButton("Save to folder", action: save).disabled(pages.isEmpty)
            }.padding(.horizontal, WatakeSpacing.md)
        }
        .sheet(isPresented: $editingCrop) { CropEditor(page: $pages[selected]) }
    }
}

private struct CropEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var page: ReviewPage
    @State private var topLeft = CGPoint(x: 0, y: 1)
    @State private var topRight = CGPoint(x: 1, y: 1)
    @State private var bottomRight = CGPoint(x: 1, y: 0)
    @State private var bottomLeft = CGPoint(x: 0, y: 0)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WatakeSpacing.lg) {
                    if let image = UIImage(data: page.source) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .overlay { cornerOverlay }
                    }
                    Text("Drag each corner. Original stays unchanged.")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.secondary)
                    cornerControls
                }
                .padding(WatakeSpacing.md)
            }
            .navigationTitle("Adjust corners")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        apply()
                        dismiss()
                    }
                }
            }
        }
    }

    private func apply() {
        let rectifier = DocumentRectifier()
        let quad = CropQuadrilateral(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft)
        Task {
            if let rectified = await rectifier.rectify(jpeg: page.source, quadrilateral: quad) {
                page.rectified = rectified
                page.detectionUncertain = false
            }
        }
    }

    private var cornerOverlay: some View {
        GeometryReader { proxy in
            ForEach(CropCorner.allCases) { corner in
                Circle()
                    .fill(WatakeColor.brand.primary)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(WatakeColor.text.onPrimary, lineWidth: 2))
                    .position(position(for: corner, in: proxy.size))
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        update(corner, with: value.location, in: proxy.size)
                    })
                    .accessibilityLabel("\(corner.label) crop corner")
            }
        }
    }

    private var cornerControls: some View {
        VStack(spacing: WatakeSpacing.sm) {
            ForEach(CropCorner.allCases) { corner in
                VStack(alignment: .leading) {
                    Text(corner.label).watakeType(.bodyEmphasis)
                    Slider(value: binding(for: corner, axis: .horizontal), in: 0 ... 1).accessibilityLabel("\(corner.label) horizontal")
                    Slider(value: binding(for: corner, axis: .vertical), in: 0 ... 1).accessibilityLabel("\(corner.label) vertical")
                }
            }
        }
    }

    private func position(for corner: CropCorner, in size: CGSize) -> CGPoint {
        let point = point(for: corner)
        return CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }

    private func update(_ corner: CropCorner, with location: CGPoint, in size: CGSize) {
        let point = CGPoint(x: min(1, max(0, location.x / size.width)), y: min(1, max(0, 1 - location.y / size.height)))
        set(point, for: corner)
    }

    private func point(for corner: CropCorner) -> CGPoint {
        switch corner {
        case .topLeft: topLeft
        case .topRight: topRight
        case .bottomRight: bottomRight
        case .bottomLeft: bottomLeft
        }
    }

    private func set(_ point: CGPoint, for corner: CropCorner) {
        switch corner {
        case .topLeft: topLeft = point
        case .topRight: topRight = point
        case .bottomRight: bottomRight = point
        case .bottomLeft: bottomLeft = point
        }
    }

    private func binding(for corner: CropCorner, axis: CropAxis) -> Binding<Double> {
        Binding(
            get: { axis == .horizontal ? point(for: corner).x : point(for: corner).y },
            set: { value in
                var point = point(for: corner)
                if axis == .horizontal {
                    point.x = value
                } else {
                    point.y = value
                }
                set(point, for: corner)
            }
        )
    }
}

private enum CropCorner: CaseIterable, Identifiable {
    case topLeft, topRight, bottomRight, bottomLeft
    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomRight: "Bottom right"
        case .bottomLeft: "Bottom left"
        }
    }
}

private enum CropAxis { case horizontal, vertical }

private struct SaveDestination: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    let pages: [ReviewPage]
    let grouping: GalleryGrouping
    @Binding var isSaving: Bool
    let onSaved: () -> Void
    @State private var folderID: UUID?
    @State private var name = "Document"
    @State private var newFolderName = ""
    @State private var showSaveError = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("Document name", text: $name)
                Picker("Folder", selection: $folderID) {
                    Text("Choose folder").tag(UUID?.none)
                    ForEach(store.activeFolders) { Text($0.name).tag(Optional($0.id)) }
                }
                if store.activeFolders.isEmpty {
                    Section("Create folder") {
                        TextField("Folder name", text: $newFolderName)
                        Button("Create folder") {
                            Task {
                                if let folder = await store.createFolder(name: newFolderName) {
                                    folderID = folder.id
                                }
                            }
                        }
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Save to folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(folderID == nil || isSaving) }
            }
        }.task { folderID = store.activeFolders.first?.id }
            .alert("Could not save capture", isPresented: $showSaveError) {
                Button("Retry") {}
            } message: {
                Text(store.errorMessage ?? "Review pages remain available to retry.")
            }
    }

    private func save() {
        guard let folderID, let folder = store.folder(for: folderID) else { return }
        isSaving = true
        Task {
            let saved = await store.save(
                pages: pages.map {
                    ImportedPage(
                        sourceData: $0.source,
                        sourceMediaType: $0.sourceMediaType,
                        sourceFileExtension: $0.sourceFileExtension,
                        rectifiedJPEG: $0.rectified
                    )
                },
                grouping: grouping,
                folder: folder,
                name: name
            )
            isSaving = false
            if saved {
                onSaved()
                dismiss()
            } else {
                showSaveError = true
            }
        }
    }
}

private enum RawCameraError: Error {
    case cancelled, unavailable, captureFailed
}

/// AVFoundation raw capture keeps scanner processing out of this mode. Only
/// encoded image bytes cross its UIKit boundary into the review model.
private struct RawCameraCapture: UIViewControllerRepresentable {
    let completion: (Result<Data, RawCameraError>) -> Void
    func makeUIViewController(context: Context) -> RawCameraController {
        let controller = RawCameraController()
        controller.completion = completion
        return controller
    }

    func updateUIViewController(_ uiViewController: RawCameraController, context: Context) {}
}

private final class RawCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    var completion: ((Result<Data, RawCameraError>) -> Void)?
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard configureSession() else {
            finish(.failure(.unavailable))
            return
        }
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        let shutter = UIButton(type: .system)
        shutter.setImage(UIImage(systemName: "circle.inset.filled"), for: .normal)
        shutter.tintColor = .white
        shutter.addTarget(self, action: #selector(capture), for: .touchUpInside)
        shutter.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shutter)
        NSLayoutConstraint.activate([
            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutter.widthAnchor.constraint(equalToConstant: 56),
            shutter.heightAnchor.constraint(equalToConstant: 56)
        ])
        Task { @MainActor in
            let status = await AVCaptureDevice.requestAccess(for: .video)
            guard status else { finish(.failure(.unavailable))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }
    }

    @objc private func capture() {
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    private func configureSession() -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
            return false
        }
        guard let device = AVCaptureDevice.default(for: .video) else {
            return false
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            return false
        }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            return false
        }
        session.addInput(input)
        session.addOutput(output)
        return true
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { finish(.failure(.captureFailed))
            return
        }
        finish(.success(data))
    }

    private func finish(_ result: Result<Data, RawCameraError>) {
        guard !didFinish else { return }
        didFinish = true
        session.stopRunning()
        dismiss(animated: true) { self.completion?(result) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !didFinish {
            finish(.failure(.cancelled))
        }
    }
}
