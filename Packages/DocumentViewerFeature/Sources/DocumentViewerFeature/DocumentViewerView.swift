#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain
    import WatermarkEditorFeature

    /// Root viewer surface: reopens a saved document by `DocumentID` and shows
    /// its ordered pages. Adapts internally between compact (full-screen +
    /// horizontal thumbnails), regular (thumbnail rail + detail), and expanded
    /// (wider rail + detail) per `RESPONSIVE.md`'s "Document Viewer" section.
    ///
    /// The caller owns `model` and keeps it alive across width-class changes so
    /// the selected document/page is never lost when the shell reflows.
    public struct DocumentViewerView: View {
        @Bindable private var model: DocumentViewerModel
        private let presetStore: any WatermarkPresetStore
        private let onClose: (() -> Void)?
        private let onWatermarkRequested: ((UUID) -> Void)?
        @FocusState private var isViewerFocused: Bool
        @State private var watermarkEditor: WatermarkEditorPresentation?

        /// `onClose` is optional: it powers an accessible Escape-key shortcut
        /// to dismiss the viewer, in addition to whatever visible back/close
        /// control the caller already provides in its own toolbar.
        public init(
            model: DocumentViewerModel,
            presetStore: any WatermarkPresetStore = UnavailableWatermarkPresetStore(),
            onWatermarkRequested: ((UUID) -> Void)? = nil,
            onClose: (() -> Void)? = nil
        ) {
            self.model = model
            self.presetStore = presetStore
            self.onWatermarkRequested = onWatermarkRequested
            self.onClose = onClose
        }

        public var body: some View {
            GeometryReader { proxy in
                let widthClass = WatakeLayout.widthClass(for: proxy.size.width)
                stateView(widthClass: widthClass)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(WatakeColor.surface.base)
            .task { model.loadIfNeeded() }
            // `onKeyPress` only fires while the modified view or a descendant
            // has focus; touch navigation alone never assigns it, so Escape
            // would otherwise never fire on iPad. Claim focus once when the
            // viewer appears (the same moment a caller's sheet/full-screen
            // cover would already be taking over the responder chain) rather
            // than reclaiming it on every render, so this never fights a
            // sheet or control for focus.
            .focusable()
            .focused($isViewerFocused)
            .onAppear { isViewerFocused = true }
            .fullScreenCover(item: $watermarkEditor) { presentation in
                WatermarkEditorView(model: presentation.model, sourceImageData: presentation.sourceImageData) {
                    watermarkEditor = nil
                }
            }
            .overlay(alignment: .bottom) {
                OCRExtractionProgress(state: model.ocrState, cancel: model.cancelTextExtraction)
            }
            .onKeyPress(.escape) {
                guard let onClose else { return .ignored }
                onClose()
                return .handled
            }
        }

        @ViewBuilder
        private func stateView(widthClass: WatakeWidthClass) -> some View {
            switch model.state {
            case .loading:
                ProgressView("Loading document")
                    .accessibilityLabel("Loading document")

            case .empty:
                WatakeEmptyState(
                    systemImage: "doc.questionmark",
                    title: "Document not found.",
                    message: "It may have been moved or deleted."
                )

            case .failure:
                WatakeEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't open this document.",
                    message: "Try again.",
                    actionTitle: "Retry",
                    actionAccessibilityIdentifier: "documentViewer.retry"
                ) {
                    model.retry()
                }

            case .content(let content):
                contentState(content, widthClass: widthClass)
            }
        }

        private func contentState(_ content: DocumentViewerContent, widthClass: WatakeWidthClass) -> some View {
            DocumentViewerContentView(content: content, widthClass: widthClass, model: model)
                .navigationTitle(content.document.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if let onWatermarkRequested {
                                onWatermarkRequested(content.document.id)
                                return
                            }
                            guard case .loaded(let data) = content.pageAsset else { return }
                            watermarkEditor = WatermarkEditorPresentation(
                                sourceImageData: data,
                                presetStore: presetStore
                            )
                        } label: {
                            Label("Watermark", systemImage: "paintbrush")
                        }
                        .disabled(!isPageLoaded(content))
                        .accessibilityHint("Creates a recipient-based watermarked copy of every page")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if model.ocrState.isExtracting {
                            Button("Cancel extraction") { model.cancelTextExtraction() }
                                .accessibilityLabel("Cancel text extraction")
                        } else {
                            Button { model.extractText() } label: {
                                Label("Extract Text", systemImage: "text.viewfinder")
                            }
                            .accessibilityHint("Extracts private text from every page on this device")
                        }
                    }
                }
        }

        private func isPageLoaded(_ content: DocumentViewerContent) -> Bool {
            if case .loaded = content.pageAsset {
                true
            } else {
                false
            }
        }
    }

    private struct OCRExtractionProgress: View {
        let state: OCRExtractionState
        let cancel: () -> Void

        var body: some View {
            if case .extracting(let completedPages, let totalPages) = state {
                HStack(spacing: WatakeSpacing.sm) {
                    ProgressView()
                    Text("Extracting text \(completedPages) of \(totalPages)")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.primary)
                    Spacer(minLength: 0)
                    WatakeButton("Cancel", variant: .secondary, accessibilityIdentifier: "documentViewer.cancelOCR", action: cancel)
                }
                .padding(WatakeSpacing.sm)
                .background(WatakeColor.surface.raised)
                .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md))
                .padding(WatakeSpacing.md)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Text extraction in progress: \(completedPages) of \(totalPages) pages")
            }
        }
    }

    /// Presentation data stays self-contained so the full-screen editor reads
    /// the exact page image that was loaded when the person tapped Watermark.
    /// The source image is passed read-only; the editor owns only its in-memory
    /// working draft.
    @MainActor
    private struct WatermarkEditorPresentation: Identifiable {
        let id = UUID()
        let sourceImageData: Data
        let model: WatermarkEditorModel

        init(sourceImageData: Data, presetStore: any WatermarkPresetStore) {
            self.sourceImageData = sourceImageData
            model = WatermarkEditorModel(presetStore: presetStore)
        }
    }

    /// Splits compact vs. regular/expanded per `RESPONSIVE.md`. Regular and
    /// expanded currently share a rail+detail structure; expanded additionally
    /// widens the rail per the shared list-column measurement.
    struct DocumentViewerContentView: View {
        let content: DocumentViewerContent
        let widthClass: WatakeWidthClass
        let model: DocumentViewerModel

        var body: some View {
            switch widthClass {
            case .compact:
                VStack(spacing: 0) {
                    DocumentPagePreview(content: content, model: model)
                        .frame(maxHeight: .infinity)
                    DocumentPageRail(content: content, model: model, axis: .horizontal)
                        .frame(height: 96)
                        .background(WatakeColor.surface.raised)
                }
            case .regular, .expanded:
                HStack(spacing: 0) {
                    DocumentPageRail(content: content, model: model, axis: .vertical)
                        .frame(width: widthClass == .expanded ? 340 : 300)
                        .background(WatakeColor.surface.raised)
                    Divider()
                    DocumentPagePreview(content: content, model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
#endif
