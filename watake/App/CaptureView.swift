import AVFoundation
import CaptureFeature
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
    @State private var reviewState = CaptureReviewState()
    @State private var isChoosingGrouping = false
    @State private var captureError: String?

    private let rectifier = DocumentRectifier()

    var body: some View {
        VStack(spacing: WatakeSpacing.xl) {
            Picker("Capture mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, WatakeSpacing.md)

            if reviewState.pages.isEmpty {
                sourcePicker
            } else {
                CaptureReviewView(
                    state: reviewState,
                    folderProvider: store,
                    saver: store,
                    rectifier: rectifier,
                    onRetake: retake,
                    onSaved: {
                        reviewState.pages = []
                    }
                )
            }
        }
        .background(WatakeColor.surface.base)
        .navigationTitle("Capture")
        .watakeDocumentScanner(isPresented: $showScanner) { result in
            switch result {
            case .success(let scan):
                reviewState.pages = scan.map {
                    CaptureReviewPage(
                        sourceData: $0.jpegData,
                        rectifiedData: $0.jpegData,
                        detectionUncertain: false
                    )
                }
                reviewState.selectedIndex = 0
            case .failure(.cancelled): break
            case .failure: captureError = "Scanner could not finish. Check camera access and try again."
            }
        }
        .sheet(isPresented: $showRawCamera) {
            RawCameraCapture { result in
                showRawCamera = false
                switch result {
                case .success(let data):
                    reviewState.pages = [
                        CaptureReviewPage(
                            sourceData: data,
                            rectifiedData: nil,
                            detectionUncertain: false
                        )
                    ]
                    reviewState.selectedIndex = 0
                case .failure(.cancelled): break
                case .failure: captureError = "Camera is unavailable. Check camera access and try again."
                }
            }
        }
        .confirmationDialog("Save selected photos", isPresented: $isChoosingGrouping, titleVisibility: .visible) {
            Button("One multi-page document") { reviewState.grouping = .oneDocument }
            Button("Separate documents") { reviewState.grouping = .separateDocuments }
            Button("Cancel", role: .cancel) { pickerItems = [] }
        } message: { Text("Choose how selected images should be added to your archive.") }
        .alert("Capture needs attention", isPresented: Binding(
            get: { captureError != nil },
            set: {
                if !$0 {
                    captureError = nil
                }
            }
        )) {
            Button("OK") {}
        } message: { Text(captureError ?? "Try again.") }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await loadGallery(newItems) }
        }
    }

    private var sourcePicker: some View {
        VStack(spacing: WatakeSpacing.md) {
            Image(systemName: mode.symbol)
                .font(.system(size: 56))
                .foregroundStyle(WatakeColor.brand.primary)
            Text(mode.description)
                .watakeType(.body)
                .foregroundStyle(WatakeColor.text.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WatakeSpacing.xl)
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
        reviewState.retake()
        pickerItems = []
        mode = .scanner
    }

    private func loadGallery(_ items: [PhotosPickerItem]) async {
        var result: [CaptureReviewPage] = []
        for item in items {
            if Task.isCancelled {
                return
            }
            guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else { continue }
            let detection = await rectifier.detect(in: data)
            let rectified = detection.isDetectionConfident
                ? await rectifier.rectify(jpegData: data, quadrilateral: detection.quadrilateral, rotationDegrees: 0)
                : nil
            let type = item.supportedContentTypes.first
            result.append(CaptureReviewPage(
                sourceData: data,
                sourceMediaType: type?.preferredMIMEType ?? "image/jpeg",
                sourceFileExtension: type?.preferredFilenameExtension ?? "jpg",
                rectifiedData: rectified,
                cropQuadrilateral: detection.quadrilateral,
                rotationDegrees: 0,
                detectionUncertain: !detection.isDetectionConfident
            ))
        }
        guard !result.isEmpty else {
            captureError = "No selected photos could be imported."
            return
        }
        reviewState.pages = result
        reviewState.selectedIndex = 0
        isChoosingGrouping = true
    }
}

extension LibraryStore: CaptureFolderProviding, CaptureSaving {
    func activeFolders() async -> [Folder] {
        activeFolders
    }

    func createFolder(name: String) async throws -> Folder {
        guard let folder = await createFolder(name: name) else {
            throw DomainValidationError.emptyName(field: "folder")
        }
        return folder
    }

    func save(
        pages: [ImportedPage],
        grouping: GalleryGrouping,
        folderID: UUID,
        name: String
    ) async throws -> [StoredDocument] {
        guard let folder = folder(for: folderID) else {
            throw ImportSaveError.targetFolderMissing
        }
        let success = await save(pages: pages, grouping: grouping, folder: folder, name: name)
        guard success else {
            throw ImportSaveError.cacheUnavailable
        }
        return documents(in: folder)
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
            guard status else {
                finish(.failure(.unavailable))
                return
            }
            // AVCaptureSession is not Sendable, but startRunning() is
            // documented as safe to call off the main thread. Capture it as
            // nonisolated(unsafe) so the background closure doesn't send
            // MainActor-isolated `self`, and starting is done off the main
            // thread as Apple recommends (startRunning blocks).
            nonisolated(unsafe) let session = self.session
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
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
        guard error == nil, let data = photo.fileDataRepresentation() else {
            finish(.failure(.captureFailed))
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
