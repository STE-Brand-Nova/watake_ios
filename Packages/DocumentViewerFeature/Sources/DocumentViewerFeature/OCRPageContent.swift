#if canImport(UIKit)
    import CoreTransferable
    import DesignSystem
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers
    import WatakeDomain

    struct OCRTextPage: View {
        let page: DocumentPage
        let extractionState: OCRExtractionState

        var body: some View {
            if let text = page.ocrText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: WatakeSpacing.sm) {
                    HStack(spacing: WatakeSpacing.xs) {
                        WatakeButton("Copy", variant: .secondary, accessibilityIdentifier: "documentViewer.copyOCR") {
                            UIPasteboard.general.string = text
                        }
                        ShareLink(item: OCRTextExport(text: text), preview: SharePreview("Extracted text")) {
                            Label("Share as .txt", systemImage: "square.and.arrow.up")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .foregroundStyle(WatakeColor.brand.primary)
                        .accessibilityLabel("Share extracted text as a text file")
                        Spacer(minLength: 0)
                    }
                    ScrollView {
                        Text(text)
                            .watakeType(.body)
                            .foregroundStyle(WatakeColor.text.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .accessibilityLabel("Extracted text")
                }
            } else {
                WatakeEmptyState(
                    systemImage: "text.viewfinder",
                    title: "No text found.",
                    message: message
                )
            }
        }

        private var message: String {
            switch extractionState {
            case .extracting:
                "Text extraction is in progress."
            case .cancelled:
                "Text extraction was cancelled."
            case .failure:
                "Text extraction failed. Try again."
            default:
                "Extract text to make this page readable and copyable."
            }
        }
    }

    struct OCRImageOverlay: View {
        let image: PlatformImage
        let blocks: [OCRBlock]

        var body: some View {
            GeometryReader { proxy in
                let fitted = aspectFitSize(imageSize: image.displaySize, in: proxy.size)
                let origin = CGPoint(
                    x: (proxy.size.width - fitted.width) / 2,
                    y: (proxy.size.height - fitted.height) / 2
                )
                ZStack(alignment: .topLeading) {
                    image.swiftUIImage
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: origin.x + fitted.width / 2, y: origin.y + fitted.height / 2)
                    ForEach(blocks) { block in
                        RoundedRectangle(cornerRadius: WatakeRadius.sm)
                            .strokeBorder(WatakeColor.status.warning, lineWidth: 2)
                            .frame(width: fitted.width * block.bounds.width, height: fitted.height * block.bounds.height)
                            .position(
                                x: origin.x + fitted.width * (block.bounds.originX + block.bounds.width / 2),
                                y: origin.y + fitted.height * (block.bounds.originY + block.bounds.height / 2)
                            )
                            .accessibilityLabel("Recognized text region")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Document with recognized text regions")
        }

        private func aspectFitSize(imageSize: CGSize, in container: CGSize) -> CGSize {
            guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
            let scale = min(container.width / imageSize.width, container.height / imageSize.height)
            return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        }
    }

    private struct OCRTextExport: Transferable {
        let text: String

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(exportedContentType: .plainText) { value in
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("watake-ocr-\(UUID().uuidString).txt")
                try Data(value.text.utf8).write(to: fileURL, options: .atomic)
                return SentTransferredFile(fileURL, allowAccessingOriginalFile: false)
            }
        }
    }
#endif
