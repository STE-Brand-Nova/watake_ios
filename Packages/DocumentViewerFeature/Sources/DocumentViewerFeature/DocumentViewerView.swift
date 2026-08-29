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
        private let watermarkedCopies: [DocumentWatermarkedCopySummary]
        private let onWatermarkedCopyRequested: ((UUID) -> Void)?
        private let onViewAllWatermarkedCopies: (() -> Void)?
        private let onRenameRequested: ((StoredDocument) -> Void)?
        private let onMoveRequested: ((StoredDocument) -> Void)?
        private let onExportRequested: ((StoredDocument) -> Void)?
        private let onDeleteRequested: ((StoredDocument) -> Void)?
        @FocusState private var isViewerFocused: Bool
        @State private var watermarkEditor: WatermarkEditorPresentation?
        @State private var pageOrganizer: OrganizePagesPresentation?
        @State private var documentPendingDeletion: StoredDocument?
        @State private var showsPageOrganizationConfirmation = false

        /// `onClose` is optional: it powers an accessible Escape-key shortcut
        /// to dismiss the viewer, in addition to whatever visible back/close
        /// control the caller already provides in its own toolbar.
        public init(
            model: DocumentViewerModel,
            presetStore: any WatermarkPresetStore = UnavailableWatermarkPresetStore(),
            onWatermarkRequested: ((UUID) -> Void)? = nil,
            watermarkedCopies: [DocumentWatermarkedCopySummary] = [],
            onWatermarkedCopyRequested: ((UUID) -> Void)? = nil,
            onViewAllWatermarkedCopies: (() -> Void)? = nil,
            onRenameRequested: ((StoredDocument) -> Void)? = nil,
            onMoveRequested: ((StoredDocument) -> Void)? = nil,
            onExportRequested: ((StoredDocument) -> Void)? = nil,
            onDeleteRequested: ((StoredDocument) -> Void)? = nil,
            onClose: (() -> Void)? = nil
        ) {
            self.model = model
            self.presetStore = presetStore
            self.onWatermarkRequested = onWatermarkRequested
            self.watermarkedCopies = watermarkedCopies
            self.onWatermarkedCopyRequested = onWatermarkedCopyRequested
            self.onViewAllWatermarkedCopies = onViewAllWatermarkedCopies
            self.onRenameRequested = onRenameRequested
            self.onMoveRequested = onMoveRequested
            self.onExportRequested = onExportRequested
            self.onDeleteRequested = onDeleteRequested
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
            .fullScreenCover(item: $pageOrganizer) { presentation in
                OrganizePagesView(model: presentation.model) {
                    showsPageOrganizationConfirmation = true
                }
            }
            .confirmationDialog(
                "Move document to Trash?",
                isPresented: deleteConfirmationBinding,
                titleVisibility: .visible,
                presenting: documentPendingDeletion
            ) { document in
                Button("Move to Trash", role: .destructive) {
                    documentPendingDeletion = nil
                    onDeleteRequested?(document)
                }
                Button("Cancel", role: .cancel) {
                    documentPendingDeletion = nil
                }
            } message: { document in
                Text("\(document.name) will remain recoverable from Trash.")
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: WatakeSpacing.sm) {
                    if showsPageOrganizationConfirmation {
                        PageOrganizationConfirmation()
                            .task {
                                try? await Task.sleep(for: .seconds(2))
                                showsPageOrganizationConfirmation = false
                            }
                    }
                    OCRExtractionProgress(state: model.ocrState, cancel: model.cancelTextExtraction)
                }
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
            DocumentViewerContentView(
                content: content,
                widthClass: widthClass,
                model: model,
                watermarkedCopies: watermarkedCopies,
                onWatermarkedCopyRequested: onWatermarkedCopyRequested,
                onViewAllWatermarkedCopies: onViewAllWatermarkedCopies
            )
            .navigationTitle(content.document.name)
            .toolbar { viewerToolbar(content) }
        }

        @ToolbarContentBuilder
        private func viewerToolbar(_ content: DocumentViewerContent) -> some ToolbarContent {
            ToolbarItem(placement: .topBarTrailing) { watermarkButton(content) }
            ToolbarItem(placement: .topBarTrailing) { documentActionsMenu(content) }
        }

        private func watermarkButton(_ content: DocumentViewerContent) -> some View {
            Button {
                if let onWatermarkRequested {
                    onWatermarkRequested(content.document.id)
                    return
                }
                guard case .loaded(let data) = content.pageAsset else { return }
                watermarkEditor = WatermarkEditorPresentation(sourceImageData: data, presetStore: presetStore)
            } label: {
                Label("Watermark", systemImage: "paintbrush")
            }
            .disabled(!isPageLoaded(content))
            .accessibilityHint("Creates a recipient-based watermarked copy of every page")
        }

        private func documentActionsMenu(_ content: DocumentViewerContent) -> some View {
            Menu {
                organizationActions
                documentMetadataActions(content.document)
                extractionAction
                recoveryAction
                deleteAction(content.document)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityHint("Shows document actions")
        }

        private var organizationActions: some View {
            Button { presentPageOrganizer() } label: {
                Label("Organize Pages", systemImage: "square.grid.2x2")
            }
            .disabled(model.ocrState.isExtracting)
        }

        @ViewBuilder
        private var recoveryAction: some View {
            Divider()
            Button { presentPageOrganizer(restoringOriginalOrder: true) } label: {
                Label("Restore Original Page Order", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canRestoreOriginalPageOrder || model.ocrState.isExtracting)
        }

        @ViewBuilder
        private func documentMetadataActions(_ document: StoredDocument) -> some View {
            if let onRenameRequested {
                Button { onRenameRequested(document) } label: { Label("Rename", systemImage: "pencil") }
            }
            if let onMoveRequested {
                Button { onMoveRequested(document) } label: { Label("Move", systemImage: "folder") }
            }
            if let onExportRequested {
                Button { onExportRequested(document) } label: { Label("Export", systemImage: "square.and.arrow.up") }
            }
        }

        @ViewBuilder
        private var extractionAction: some View {
            Divider()
            if model.ocrState.isExtracting {
                Button("Cancel Text Extraction") { model.cancelTextExtraction() }
            } else {
                Button { model.extractText() } label: { Label("Extract Text", systemImage: "text.viewfinder") }
            }
        }

        @ViewBuilder
        private func deleteAction(_ document: StoredDocument) -> some View {
            if onDeleteRequested != nil {
                Divider()
                Button(role: .destructive) { documentPendingDeletion = document } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }

        private var deleteConfirmationBinding: Binding<Bool> {
            Binding(
                get: { documentPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        documentPendingDeletion = nil
                    }
                }
            )
        }

        private func presentPageOrganizer(restoringOriginalOrder: Bool = false) {
            guard let organizer = model.makeOrganizePagesModel(restoringOriginalOrder: restoringOriginalOrder) else { return }
            pageOrganizer = OrganizePagesPresentation(model: organizer)
        }

        private func isPageLoaded(_ content: DocumentViewerContent) -> Bool {
            if case .loaded = content.pageAsset {
                true
            } else {
                false
            }
        }
    }

    @MainActor
    private struct OrganizePagesPresentation: Identifiable {
        let id = UUID()
        let model: OrganizePagesModel
    }

    private struct PageOrganizationConfirmation: View {
        var body: some View {
            Label("Pages reorganized.", systemImage: "checkmark.circle.fill")
                .watakeType(.bodyEmphasis)
                .foregroundStyle(WatakeColor.text.primary)
                .padding(.horizontal, WatakeSpacing.md)
                .padding(.vertical, WatakeSpacing.sm)
                .background(WatakeColor.surface.raised)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(WatakeColor.border.subtle, lineWidth: 1))
                .padding(WatakeSpacing.md)
                .accessibilityLabel("Pages reorganized")
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
        let watermarkedCopies: [DocumentWatermarkedCopySummary]
        let onWatermarkedCopyRequested: ((UUID) -> Void)?
        let onViewAllWatermarkedCopies: (() -> Void)?

        var body: some View {
            switch widthClass {
            case .compact:
                VStack(spacing: 0) {
                    documentDetail
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
                    documentDetail
                }
            }
        }

        private var documentDetail: some View {
            VStack(spacing: 0) {
                DocumentPagePreview(content: content, model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                if !watermarkedCopies.isEmpty {
                    DocumentWatermarkedCopiesStrip(
                        copies: watermarkedCopies,
                        onOpenCopy: { copyID in
                            onWatermarkedCopyRequested?(copyID)
                        },
                        onViewAll: {
                            onViewAllWatermarkedCopies?()
                        }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
#endif
