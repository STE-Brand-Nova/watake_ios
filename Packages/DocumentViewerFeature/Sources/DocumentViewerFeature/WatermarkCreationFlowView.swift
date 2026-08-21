#if canImport(SwiftUI) && canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain
    import WatermarkEditorFeature

    @MainActor
    public struct WatermarkCreationFlowView: View {
        public typealias CreateAction = @MainActor (
            _ recipientName: String,
            _ purpose: String?,
            _ config: WatermarkConfig,
            _ imageData: Data?,
            _ progress: @escaping @Sendable (Int, Int) -> Void
        ) async -> WatermarkIssuance?
        public typealias ShareAction = @MainActor (WatermarkIssuance) async -> [URL]

        private enum Step: Int, CaseIterable { case details, design, review, success }

        private let documents: [StoredDocument]
        private let recipients: [WatermarkRecipient]
        private let sourceImageData: Data
        private let create: CreateAction
        private let share: ShareAction
        private let onViewCopies: () -> Void
        private let onDismiss: () -> Void
        @State private var step: Step = .details
        @State private var recipientName = ""
        @State private var purpose = ""
        @State private var isCreating = false
        @State private var completedPages = 0
        @State private var totalPages = 0
        @State private var issuance: WatermarkIssuance?
        @State private var shareItems: WatermarkShareItems?
        @State private var isPreparingShare = false
        @State private var model: WatermarkEditorModel

        public init(
            documents: [StoredDocument],
            recipients: [WatermarkRecipient],
            sourceImageData: Data,
            presetStore: any WatermarkPresetStore,
            assetStore: any DocumentAssetStore,
            initialConfig: WatermarkConfig? = nil,
            initialRecipientName: String = "",
            initialPurpose: String? = nil,
            create: @escaping CreateAction,
            share: @escaping ShareAction,
            onViewCopies: @escaping () -> Void,
            onDismiss: @escaping () -> Void
        ) {
            self.documents = documents
            self.recipients = recipients
            self.sourceImageData = sourceImageData
            self.create = create
            self.share = share
            self.onViewCopies = onViewCopies
            self.onDismiss = onDismiss
            _recipientName = State(initialValue: initialRecipientName)
            _purpose = State(initialValue: initialPurpose ?? "")
            let starter = initialConfig.map(WatermarkEditorDraft.init(config:)) ?? WatermarkEditorDraft(
                body: EditableWatermarkTextLayer(text: "For {recipient} · {date}", enabled: true, opacity: 0.38)
            )
            _model = State(initialValue: WatermarkEditorModel(
                draft: starter,
                selectedTab: .body,
                presetStore: presetStore,
                assetStore: assetStore
            ))
        }

        public var body: some View {
            NavigationStack {
                content
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(step == .success ? "Done" : "Cancel", action: onDismiss)
                                .disabled(isCreating)
                        }
                    }
            }
            .interactiveDismissDisabled(isCreating)
            .sheet(item: $shareItems) { items in
                WatermarkActivityView(items: items.urls)
            }
        }

        @ViewBuilder private var content: some View {
            switch step {
            case .details: details
            case .design:
                WatermarkEditorView(
                    model: model,
                    sourceImageData: sourceImageData,
                    actionTitle: "Review",
                    previewRecipient: recipientName,
                    previewPurpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    isActionDisabled: model.renderedPreviewData == nil || model.previewRenderFailed
                ) {
                    step = .review
                }
            case .review: review
            case .success: success
            }
        }

        private var details: some View {
            Form {
                Section("Scope") {
                    Label(scopeSummary, systemImage: documents.count == 1 ? "doc.text" : "doc.on.doc")
                    Text("The same watermark will be applied to every page. Individual page overrides are not changed in this release.")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.secondary)
                }
                Section("Recipient") {
                    TextField("Person or organization", text: $recipientName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("watermarkFlow.recipient")
                    if !recipients.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(recipients) { recipient in
                                    Button(recipient.displayName) { recipientName = recipient.displayName }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
                Section("Purpose or reference (optional)") {
                    TextField("For example: Job application", text: $purpose, axis: .vertical)
                }
                Section {
                    WatakeButton("Design Watermark", variant: .primary, accessibilityIdentifier: "watermarkFlow.design") {
                        recipientName = recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
                        step = .design
                    }
                    .disabled(recipientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }

        private var review: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: WatakeSpacing.lg) {
                    summaryCard(title: "Recipient", value: recipientName)
                    if !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        summaryCard(title: "Purpose", value: purpose)
                    }
                    summaryCard(title: "Copies", value: scopeSummary)
                    summaryCard(title: "Watermark", value: watermarkSummary)
                    if isCreating {
                        ProgressView(value: Double(completedPages), total: Double(max(totalPages, 1))) {
                            Text("Creating page \(completedPages) of \(totalPages)")
                        }
                    }
                    WatakeButton(
                        "Create \(documents.count) Cop\(documents.count == 1 ? "y" : "ies")",
                        variant: .primary,
                        accessibilityIdentifier: "watermarkFlow.create"
                    ) { startCreation() }
                        .disabled(isCreating || !canCreate)
                    Button("Back to Design") { step = .design }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(isCreating)
                }
                .padding(WatakeSpacing.md)
            }
            .background(WatakeColor.surface.base)
        }

        private var success: some View {
            VStack(spacing: WatakeSpacing.lg) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(WatakeColor.status.success)
                Text("Watermarked copies created")
                    .watakeType(.title1)
                Text("\(createdCopyCount) immutable cop\(createdCopyCount == 1 ? "y" : "ies") saved for \(recipientName).")
                    .watakeType(.body)
                    .foregroundStyle(WatakeColor.text.secondary)
                    .multilineTextAlignment(.center)
                WatakeButton("View in Copies", variant: .primary, accessibilityIdentifier: "watermarkFlow.viewCopies") {
                    onViewCopies()
                }
                Button {
                    prepareShare()
                } label: {
                    if isPreparingShare {
                        ProgressView()
                    } else {
                        Label("Share PDFs", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .disabled(isPreparingShare)
                Button("Done", action: onDismiss)
                    .frame(minHeight: 44)
            }
            .padding(WatakeSpacing.xl)
            .frame(maxWidth: 520, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .background(WatakeColor.surface.base)
        }

        private var title: String {
            switch step {
            case .details: "Watermark Details"
            case .design: "Design Watermark"
            case .review: "Review Copies"
            case .success: "Copies Created"
            }
        }

        private var scopeSummary: String {
            let pages = documents.reduce(0) { $0 + $1.pages.count }
            return "\(documents.count) original\(documents.count == 1 ? "" : "s") · \(pages) page\(pages == 1 ? "" : "s")"
        }

        private var createdCopyCount: Int {
            issuance?.renditions.count ?? documents.count
        }

        private var watermarkSummary: String {
            let config = model.draft.watermarkConfig
            let textCount = config.renderableTextLayersInCompositionOrder.count
            let image = config.image?.enabled == true ? " and image" : ""
            return "\(textCount) text layer\(textCount == 1 ? "" : "s")\(image) · \(config.layoutMode.rawValue)"
        }

        private var canCreate: Bool {
            let config = model.draft.watermarkConfig
            return !recipientName.isEmpty && !model.previewRenderFailed &&
                (!config.usesPurposeToken || !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
                config.hasVisibleLayer
        }

        private func summaryCard(title: String, value: String) -> some View {
            WatakeCard {
                VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
                    Text(title).watakeType(.overline).foregroundStyle(WatakeColor.text.secondary)
                    Text(value).watakeType(.bodyEmphasis).foregroundStyle(WatakeColor.text.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private func startCreation() {
            guard canCreate else { return }
            isCreating = true
            completedPages = 0
            totalPages = documents.reduce(0) { $0 + $1.pages.count }
            let progress: @Sendable (Int, Int) -> Void = { completed, total in
                Task { @MainActor in
                    completedPages = completed
                    totalPages = total
                }
            }
            Task {
                issuance = await create(
                    recipientName,
                    purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : purpose,
                    model.draft.watermarkConfig,
                    model.watermarkImageData(),
                    progress
                )
                isCreating = false
                if issuance != nil {
                    step = .success
                }
            }
        }

        private func prepareShare() {
            guard let issuance else { return }
            isPreparingShare = true
            Task {
                let urls = await share(issuance)
                isPreparingShare = false
                if !urls.isEmpty {
                    shareItems = WatermarkShareItems(urls: urls)
                }
            }
        }
    }

    private struct WatermarkShareItems: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    private struct WatermarkActivityView: UIViewControllerRepresentable {
        let items: [URL]

        func makeUIViewController(context _: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }

        func updateUIViewController(_: UIActivityViewController, context _: Context) {}
    }

    extension String {
        fileprivate var nilIfEmpty: String? {
            isEmpty ? nil : self
        }
    }
#endif
