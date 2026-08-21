import DesignSystem
import DocumentViewerFeature
import SwiftUI
import UIKit
import WatakeDomain

struct WatermarkedCopiesView: View {
    @Bindable var store: LibraryStore
    let onOpenOriginal: (StoredDocument) -> Void
    @State private var query = ""
    @State private var selected: CopySelection?
    @State private var reissue: ReissuePresentation?

    var body: some View {
        Group {
            if groups.isEmpty {
                WatakeEmptyState(
                    systemImage: "doc.on.doc",
                    title: query.isEmpty ? "No watermarked copies yet." : "No matches.",
                    message: query.isEmpty
                        ? "Create a recipient-based copy from a document or folder."
                        : "Try a recipient, purpose, or original document name."
                )
            } else {
                List(groups) { group in
                    Section {
                        ForEach(group.copies) { copy in
                            Button {
                                selected = CopySelection(rendition: copy.rendition, issuance: copy.issuance)
                            } label: {
                                HStack(spacing: WatakeSpacing.md) {
                                    RenditionThumbnail(store: store, rendition: copy.rendition)
                                    VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
                                        Text(copy.rendition.originalNameSnapshot)
                                            .watakeType(.bodyEmphasis)
                                            .foregroundStyle(WatakeColor.text.primary)
                                        let pageLabel = "\(copy.rendition.pages.count) page\(copy.rendition.pages.count == 1 ? "" : "s")"
                                        let dateLabel = copy.issuance.createdAt.formatted(date: .abbreviated, time: .omitted)
                                        Text("v\(copy.rendition.version) · \(pageLabel) · \(dateLabel)")
                                            .watakeType(.caption)
                                            .foregroundStyle(WatakeColor.text.secondary)
                                        if let purpose = copy.issuance.purpose {
                                            Text(purpose).watakeType(.caption).foregroundStyle(WatakeColor.text.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(WatakeColor.text.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Label(group.name, systemImage: "person.crop.circle")
                            Spacer()
                            Text("\(group.copies.count)")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(WatakeColor.surface.base)
        .navigationTitle("Watermarked Copies")
        .searchable(text: $query, prompt: "Recipient, purpose, or original")
        .task { await store.load() }
        .sheet(item: $selected) { selection in
            CopyDetailView(
                store: store,
                selection: selection,
                onViewOriginal: onOpenOriginal,
                onCreateAnother: { prepareReissue(selection) }
            )
        }
        .fullScreenCover(item: $reissue) { presentation in
            WatermarkCreationFlowView(
                documents: [presentation.document],
                recipients: store.watermarkRecipients,
                sourceImageData: presentation.sourceImageData,
                presetStore: store.watermarkPresetStore,
                assetStore: store.watermarkAssetStore,
                initialConfig: presentation.selection.issuance.templateConfig,
                initialRecipientName: presentation.selection.issuance.recipientNameSnapshot,
                initialPurpose: presentation.selection.issuance.purpose,
                create: { recipient, purpose, config, imageData, progress in
                    await store.createWatermarkedCopies(
                        request: WatermarkCopyRequest(
                            documentIDs: [presentation.document.id],
                            recipientName: recipient,
                            purpose: purpose,
                            templateConfig: config,
                            imageData: imageData
                        ),
                        progress: progress
                    )
                },
                share: { issuance in await store.exportURLs(for: issuance) },
                onViewCopies: {
                    store.cleanupTemporaryExports()
                    reissue = nil
                },
                onDismiss: {
                    store.cleanupTemporaryExports()
                    reissue = nil
                }
            )
        }
    }

    private var groups: [RecipientCopyGroup] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let copies = store.watermarkIssuances.flatMap { issuance in
            issuance.renditions.filter { $0.deletedAt == nil }.map { CopyRow(issuance: issuance, rendition: $0) }
        }.filter { row in
            guard !normalized.isEmpty else { return true }
            return row.issuance.recipientNameSnapshot.lowercased().contains(normalized) ||
                row.issuance.purpose?.lowercased().contains(normalized) == true ||
                row.rendition.originalNameSnapshot.lowercased().contains(normalized) ||
                "v\(row.rendition.version)".contains(normalized)
        }
        return Dictionary(grouping: copies, by: { $0.issuance.recipientId?.uuidString ?? $0.issuance.recipientNameSnapshot.lowercased() })
            .map { key, values in
                RecipientCopyGroup(
                    id: key,
                    name: values[0].issuance.recipientNameSnapshot,
                    copies: values.sorted { $0.rendition.createdAt > $1.rendition.createdAt }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func prepareReissue(_ selection: CopySelection) {
        guard let document = store.documentIncludingTrash(id: selection.rendition.documentId), document.deletedAt == nil else {
            store.errorMessage = "Restore the original before creating another copy."
            return
        }
        Task {
            guard let data = await store.watermarkPreviewData(for: document) else {
                store.errorMessage = "The original preview could not be loaded."
                return
            }
            reissue = ReissuePresentation(selection: selection, document: document, sourceImageData: data)
        }
    }
}

private struct CopyRow: Identifiable {
    let issuance: WatermarkIssuance
    let rendition: WatermarkRendition
    var id: UUID {
        rendition.id
    }
}

private struct RecipientCopyGroup: Identifiable {
    let id: String
    let name: String
    let copies: [CopyRow]
}

private struct CopySelection: Identifiable {
    let rendition: WatermarkRendition
    let issuance: WatermarkIssuance
    var id: UUID {
        rendition.id
    }
}

private struct ReissuePresentation: Identifiable {
    let id = UUID()
    let selection: CopySelection
    let document: StoredDocument
    let sourceImageData: Data
}

private struct RenditionThumbnail: View {
    @Bindable var store: LibraryStore
    let rendition: WatermarkRendition
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "doc.badge.checkmark").foregroundStyle(WatakeColor.text.secondary)
            }
        }
        .frame(width: 48, height: 60)
        .background(WatakeColor.surface.sunken)
        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
        .task(id: rendition.id) {
            image = await store.watermarkRenditionPreviewData(rendition).flatMap(UIImage.init(data:))
        }
        .accessibilityHidden(true)
    }
}

private struct CopyDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    let selection: CopySelection
    let onViewOriginal: (StoredDocument) -> Void
    let onCreateAnother: () -> Void
    @State private var image: UIImage?
    @State private var exportURL: URL?
    @State private var isPreparingPDF = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WatakeSpacing.lg) {
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            ProgressView("Loading copy")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .background(WatakeColor.surface.sunken)
                    .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.lg))

                    WatakeCard {
                        VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                            Text(selection.issuance.recipientNameSnapshot).watakeType(.title2)
                            Text("\(selection.rendition.originalNameSnapshot) · Version \(selection.rendition.version)")
                            let pageLabel = "\(selection.rendition.pages.count) page\(selection.rendition.pages.count == 1 ? "" : "s")"
                            Text("\(pageLabel) · \(selection.rendition.createdAt.formatted())")
                                .watakeType(.caption).foregroundStyle(WatakeColor.text.secondary)
                            if let purpose = selection.issuance.purpose {
                                Text(purpose).watakeType(.body)
                            }
                            if store.documentIncludingTrash(id: selection.rendition.documentId)?.deletedAt != nil {
                                Label("Original in Trash", systemImage: "trash")
                                    .foregroundStyle(WatakeColor.status.warning)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let original = store.documentIncludingTrash(id: selection.rendition.documentId) {
                        Button {
                            dismiss()
                            onViewOriginal(original)
                        } label: { Label("View Original", systemImage: "doc.text.magnifyingglass") }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                    }
                    Button {
                        dismiss()
                        onCreateAnother()
                    } label: { Label("Create Another Copy", systemImage: "plus.square.on.square") }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)

                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                            .tint(WatakeColor.brand.primary)
                            .frame(minHeight: 44)
                    } else {
                        Button { preparePDF() } label: {
                            if isPreparingPDF {
                                ProgressView()
                            } else {
                                Label("Prepare PDF", systemImage: "doc.richtext")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPreparingPDF)
                    }
                    Button("Move Copy to Trash", role: .destructive) {
                        Task {
                            if await store.trashWatermarkRendition(selection.rendition) {
                                dismiss()
                            }
                        }
                    }
                    .frame(minHeight: 44)
                }
                .padding(WatakeSpacing.md)
            }
            .navigationTitle("Watermarked Copy")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                image = await store.watermarkRenditionPreviewData(
                    selection.rendition,
                    maxPixelSize: 1600
                ).flatMap(UIImage.init(data:))
            }
            .onDisappear {
                store.cleanupTemporaryExports()
            }
        }
    }

    private func preparePDF() {
        isPreparingPDF = true
        Task {
            exportURL = await store.exportURL(for: selection.rendition, recipientName: selection.issuance.recipientNameSnapshot)
            isPreparingPDF = false
        }
    }
}
