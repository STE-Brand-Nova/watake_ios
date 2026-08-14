import ArchiveServices
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
    @State private var isImportingFiles = false
    @State private var reviewState = CaptureReviewState()
    @State private var isChoosingGrouping = false
    @State private var captureError: String?
    @State private var importTask: Task<Void, Never>?
    @State private var importRevision = 0
    @State private var isImportingMedia = false
    @State private var showGroupingAfterImportWarning = false

    let onSaved: (UUID) -> Void

    private let rectifier = DocumentRectifier()

    init(store: LibraryStore, onSaved: @escaping (UUID) -> Void = { _ in }) {
        self.store = store
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: WatakeSpacing.xl) {
            Picker("Capture mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, WatakeSpacing.md)
            .disabled(isImportingMedia)

            if reviewState.pages.isEmpty {
                sourcePicker
            } else {
                CaptureReviewView(
                    state: reviewState,
                    folderProvider: store,
                    saver: store,
                    rectifier: rectifier,
                    onRetake: retake,
                    onSaved: { folderID in
                        reviewState.pages = []
                        onSaved(folderID)
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
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.jpeg, .png, .heic, .tiff, .pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                guard urls.count <= CaptureImportSourceAdapter.maximumSelectionCount else {
                    captureError = "Choose up to 20 images."
                    return
                }
                startImport { revision in
                    await loadFiles(Array(urls), revision: revision)
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    captureError = "No selected files could be imported."
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
                    if showGroupingAfterImportWarning {
                        showGroupingAfterImportWarning = false
                        isChoosingGrouping = true
                    }
                }
            }
        )) {
            Button("OK") {}
        } message: {
            Text(captureError ?? "Try again.")
        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            startImport { revision in
                await loadGallery(newItems, revision: revision)
            }
        }
        .onDisappear {
            cancelImport()
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
                    .disabled(isImportingMedia)
            case .scanner:
                WatakeButton("Scan document") { showScanner = true }
                    .disabled(isImportingMedia)
            case .gallery:
                HStack(spacing: WatakeSpacing.md) {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: CaptureImportSourceAdapter.maximumSelectionCount,
                        matching: .images
                    ) {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.watake(.primary))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Import images from Photos")
                    .disabled(isImportingMedia)

                    Button {
                        isImportingFiles = true
                    } label: {
                        Label("Files", systemImage: "folder")
                    }
                    .buttonStyle(.watake(.secondary))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Import images from Files")
                    .disabled(isImportingMedia)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retake() {
        cancelImport()
        reviewState.retake()
        pickerItems = []
        mode = .scanner
    }

    private func startImport(_ operation: @escaping (Int) async -> Void) {
        importTask?.cancel()
        importRevision &+= 1
        let revision = importRevision
        isImportingMedia = true
        importTask = Task {
            await operation(revision)
            guard !Task.isCancelled, revision == importRevision else { return }
            isImportingMedia = false
            importTask = nil
        }
    }

    private func cancelImport() {
        importTask?.cancel()
        importTask = nil
        importRevision &+= 1
        isImportingMedia = false
    }

    private func loadGallery(_ items: [PhotosPickerItem], revision: Int) async {
        var data: [Data?] = []
        data.reserveCapacity(items.count)
        for item in items.prefix(CaptureImportSourceAdapter.maximumSelectionCount) {
            guard isCurrentImport(revision) else { return }
            let itemData = try? await item.loadTransferable(type: Data.self)
            data.append(itemData)
        }
        guard isCurrentImport(revision) else { return }
        let batch = await CaptureImportSourceAdapter.photos(data: data)
        await loadImportedMedia(batch, revision: revision)
    }

    private func loadFiles(_ urls: [URL], revision: Int) async {
        guard isCurrentImport(revision) else { return }
        let batch = await CaptureImportSourceAdapter.files(urls: urls)
        guard isCurrentImport(revision) else { return }
        await loadImportedMedia(batch, revision: revision)
    }

    private func loadImportedMedia(_ batch: CaptureImportBatch, revision: Int) async {
        let result = await CaptureImportPipeline(rectifier: rectifier).makePages(from: batch.media)
        guard isCurrentImport(revision) else { return }
        guard !result.isEmpty else {
            captureError = "No selected images could be imported."
            return
        }
        reviewState.pages = result
        reviewState.selectedIndex = 0
        if batch.failedCount > 0 {
            showGroupingAfterImportWarning = true
            let noun = batch.failedCount == 1 ? "image" : "images"
            captureError = "\(batch.failedCount) selected \(noun) could not be imported. "
                + "Review the imported pages and try the missing files again."
        } else {
            isChoosingGrouping = true
        }
    }

    private func isCurrentImport(_ revision: Int) -> Bool {
        !Task.isCancelled && revision == importRevision
    }
}

extension LibraryStore: CaptureFolderProviding, CaptureSaving {
    func activeFolders() async -> [Folder] {
        activeFolders
    }

    func mostRecentlyUsedFolderID() async -> UUID? {
        mostRecentlyUsedFolder
    }

    func createFolder(name: String) async throws -> Folder {
        try Task.checkCancellation()
        let candidate = Folder(id: UUID(), name: name, colorHex: ArchiveTagPalette.colors[8], createdAt: .now)
        try candidate.validate()
        try Task.checkCancellation()
        guard let folder = await createFolder(name: name) else { throw ImportSaveError.cacheUnavailable }
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
        markFolderUsed(folderID)
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
