#if canImport(SwiftUI) && canImport(UIKit) && canImport(VisionKit)
    import SwiftUI
    import UIKit
    import VisionKit

    @MainActor
    extension View {
        /// Presents VisionKit as an immersive full-screen flow at every width.
        /// VisionKit owns capture, edge guidance, multi-page review, crop, and
        /// perspective correction.
        public func watakeDocumentScanner(
            isPresented: Binding<Bool>,
            completion: @escaping @MainActor (Result<[ScannedPage], NativeDocumentScannerError>) -> Void
        ) -> some View {
            modifier(NativeDocumentScannerPresentation(isPresented: isPresented, completion: completion))
        }
    }

    @MainActor
    private struct NativeDocumentScannerPresentation: ViewModifier {
        @Binding var isPresented: Bool
        let completion: NativeDocumentScanner.Completion

        func body(content: Content) -> some View {
            content
                .fullScreenCover(isPresented: scannerPresentationBinding) {
                    NativeDocumentScanner(completion: completion)
                        .ignoresSafeArea()
                }
                .onAppear(perform: handleAvailability)
                .onChange(of: isPresented) { _, _ in
                    handleAvailability()
                }
        }

        private var scannerPresentationBinding: Binding<Bool> {
            Binding(
                get: { isPresented && VNDocumentCameraViewController.isSupported },
                set: { isPresented = $0 }
            )
        }

        private func handleAvailability() {
            guard isPresented, !VNDocumentCameraViewController.isSupported else {
                return
            }
            isPresented = false
            completion(.failure(.unavailable))
        }
    }

    @MainActor
    struct NativeDocumentScanner: UIViewControllerRepresentable {
        typealias Completion = @MainActor (Result<[ScannedPage], NativeDocumentScannerError>) -> Void

        private let completion: Completion

        init(completion: @escaping Completion) {
            self.completion = completion
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(completion: completion)
        }

        func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
            let controller = VNDocumentCameraViewController()
            controller.delegate = context.coordinator
            context.coordinator.attach(controller)
            return controller
        }

        func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

        static func dismantleUIViewController(
            _ uiViewController: VNDocumentCameraViewController,
            coordinator: Coordinator
        ) {
            uiViewController.delegate = nil
            coordinator.cancelIfUnfinished()
        }

        @MainActor
        final class Coordinator: NSObject {
            private let completionGate: ScanCompletionGate<Result<[ScannedPage], NativeDocumentScannerError>>
            private weak var controller: VNDocumentCameraViewController?
            private var hasFinished = false

            init(completion: @escaping Completion) {
                completionGate = ScanCompletionGate(completion: completion)
            }

            func attach(_ controller: VNDocumentCameraViewController) {
                self.controller = controller
            }

            func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
                finish(.failure(.cancelled), dismissing: controller)
            }

            func documentCameraViewController(
                _ controller: VNDocumentCameraViewController,
                didFailWithError error: Error
            ) {
                _ = error
                finish(.failure(.visionKitFailure), dismissing: controller)
            }

            func documentCameraViewController(
                _ controller: VNDocumentCameraViewController,
                didFinishWith scan: VNDocumentCameraScan
            ) {
                guard scan.pageCount > 0 else {
                    finish(.failure(.noPages), dismissing: controller)
                    return
                }

                var pages: [ScannedPage] = []
                pages.reserveCapacity(scan.pageCount)
                for index in 0 ..< scan.pageCount {
                    guard let data = scan.imageOfPage(at: index).jpegData(compressionQuality: 1) else {
                        finish(.failure(.imageEncodingFailed), dismissing: controller)
                        return
                    }
                    pages.append(ScannedPage(jpegData: data))
                }
                finish(.success(pages), dismissing: controller)
            }

            func cancelIfUnfinished() {
                finish(.failure(.cancelled), dismissing: nil)
            }

            private func finish(
                _ result: Result<[ScannedPage], NativeDocumentScannerError>,
                dismissing controller: VNDocumentCameraViewController?
            ) {
                guard !hasFinished, let completion = completionGate.takeCompletion() else {
                    return
                }
                hasFinished = true
                self.controller = nil
                controller?.delegate = nil
                guard let controller, controller.presentingViewController != nil else {
                    completion(result)
                    return
                }
                controller.dismiss(animated: true) {
                    completion(result)
                }
            }
        }
    }

    extension NativeDocumentScanner.Coordinator: @MainActor VNDocumentCameraViewControllerDelegate {}
#endif
