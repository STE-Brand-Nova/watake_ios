//
//  ExportReviewView.swift
//  ExportFeature
//

import DesignSystem
import SwiftUI
import WatakeDomain

public struct ExportShareItem: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
}

#if canImport(UIKit)
    import UIKit

    public struct ExportShareSheet: UIViewControllerRepresentable {
        public let activityItems: [Any]
        public let onComplete: () -> Void

        public init(activityItems: [Any], onComplete: @escaping () -> Void) {
            self.activityItems = activityItems
            self.onComplete = onComplete
        }

        public func makeUIViewController(context: Context) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            controller.completionWithItemsHandler = { _, _, _, _ in
                onComplete()
            }
            return controller
        }

        public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }
#endif

public struct ExportReviewView: View {
    @State private var model: ExportFeatureModel
    @State private var isSettingsPresented = false
    @State private var exportShareItem: ExportShareItem?
    @Environment(\.dismiss) private var dismiss

    public init(model: ExportFeatureModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        GeometryReader { geometry in
            Group {
                if WatakeLayout.widthClass(for: geometry.size.width) == .compact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if case .exporting(let progress) = model.state {
                ExportProgressOverlay(
                    progress: progress,
                    onCancel: { model.cancelExport() }
                )
            }
        }
        .alert(String(localized: "Export Failed", comment: "Alert title for export failure"), isPresented: Binding(
            get: {
                if case .failed = model.state {
                    return true
                }
                return false
            },
            set: { _ in model.cleanup() }
        )) {
            Button(String(localized: "Retry", comment: "Retry button"), action: { model.retry() })
            Button(String(localized: "Cancel", comment: "Cancel button"), role: .cancel, action: { model.cleanup() })
        } message: {
            if case .failed(let error) = model.state {
                Text(errorMessage(for: error))
            }
        }
        .confirmationDialog(
            String(localized: "Large Export File", comment: "Title for large export warning"),
            isPresented: Binding(
                get: {
                    if case .preflightWarning = model.state {
                        return true
                    }
                    return false
                },
                set: { isPresented in
                    if !isPresented {
                        model.cancelWarning()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Continue Export", comment: "Continue export despite warning"), action: { model.confirmLargeExport() })
            Button(String(localized: "Cancel", comment: "Cancel export"), role: .cancel, action: { model.cancelWarning() })
        } message: {
            if case .preflightWarning(let bytes) = model.state {
                let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                Text(String(
                    localized: "The estimated file size is \(formattedSize). This might take a while.",
                    comment: "Message warning about large export size"
                ))
            }
        }
        .confirmationDialog(
            String(localized: "Large File Generated", comment: "Title for actual size export warning"),
            isPresented: Binding(
                get: {
                    if case .actualSizeWarning = model.state {
                        return true
                    }
                    return false
                },
                set: { isPresented in
                    if !isPresented {
                        model.cancelWarning()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Share PDF", comment: "Share PDF button"), action: { model.confirmActualSizeExport() })
            Button(String(localized: "Cancel", comment: "Cancel export"), role: .cancel, action: { model.cleanup() })
        } message: {
            if case .actualSizeWarning(let bytes, _) = model.state {
                let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                Text(String(
                    localized: "The generated PDF is \(formattedSize). Would you like to proceed with sharing?",
                    comment: "Message warning about actual exported file size"
                ))
            }
        }
        #if canImport(UIKit)
        .sheet(item: $exportShareItem) { shareItem in
            ExportShareSheet(activityItems: [shareItem.url]) {
                model.cleanup()
                dismiss()
            }
        }
        #endif
        .onChange(of: model.state) { _, newState in
            switch newState {
            case .completed(let url, _):
                exportShareItem = ExportShareItem(url: url)
            case .cancelled:
                dismiss()
            default:
                break
            }
        }
    }

    private var compactLayout: some View {
        NavigationStack {
            contentList
                .safeAreaInset(edge: .bottom) {
                    WatakeStickyActionBar {
                        createButton
                    }
                }
                .navigationTitle(String(localized: "Export PDF", comment: "Navigation title for export view"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel", comment: "Cancel button")) {
                            model.cleanup()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(String(localized: "Settings", comment: "Settings button")) {
                            isSettingsPresented = true
                        }
                    }
                }
                .sheet(isPresented: $isSettingsPresented) {
                    NavigationStack {
                        ScrollView {
                            ExportSettingsInspector(model: model)
                                .padding()
                        }
                        .navigationTitle(String(localized: "Settings", comment: "Settings navigation title"))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(String(localized: "Done", comment: "Done button")) {
                                    isSettingsPresented = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
        }
    }

    private var regularLayout: some View {
        NavigationStack {
            HStack(spacing: WatakeSpacing.md) {
                contentList
                    .frame(maxWidth: .infinity)

                Divider()

                VStack {
                    ScrollView {
                        ExportSettingsInspector(model: model)
                            .padding()
                    }

                    WatakeStickyActionBar {
                        createButton
                    }
                }
                .frame(width: 320)
            }
            .frame(maxWidth: 1100, alignment: .center)
            .navigationTitle(String(localized: "Export PDF", comment: "Navigation title for export view"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Cancel button")) {
                        model.cleanup()
                        dismiss()
                    }
                }
            }
        }
    }

    private var contentList: some View {
        List {
            if let draft = model.draft {
                ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                    pageRow(for: item, totalPages: draft.items.count, index: index)
                }
                .onMove { indices, newOffset in
                    model.movePage(from: indices, to: newOffset)
                }
            } else {
                Text(String(localized: "Loading...", comment: "Loading indicator"))
                    .foregroundStyle(WatakeColor.text.secondary)
            }
        }
        .listStyle(.plain)
        #if os(iOS)
            .environment(\.editMode, .constant(.active))
        #endif
    }

    private func pageRow(for item: BulkExportDraft.PageItem, totalPages: Int, index: Int) -> some View {
        HStack(spacing: WatakeSpacing.md) {
            WatakeDragHandle()
            pageThumbnail(index: index)
            pageLabels(for: item)
            Spacer()
            includeToggle(for: item)
        }
        .padding(.vertical, WatakeSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.documentName), Page \(item.sourcePageIndex + 1) of \(item.sourceTotalPages), Position \(index + 1)")
        .accessibilityHint(String(localized: "Double tap to toggle inclusion", comment: "Accessibility hint for page inclusion"))
        .accessibilityAction(named: String(localized: "Move Up", comment: "Accessibility action to move item up")) {
            announceMove(model.movePageUp(pageID: item.id))
        }
        .accessibilityAction(named: String(localized: "Move Down", comment: "Accessibility action to move item down")) {
            announceMove(model.movePageDown(pageID: item.id))
        }
    }

    private func pageThumbnail(index: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: WatakeRadius.sm)
                .fill(WatakeColor.surface.sunken)
                .frame(width: 50, height: 65)

            VStack(spacing: 2) {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                    .foregroundStyle(WatakeColor.brand.primary)
                Text("#\(index + 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WatakeColor.text.secondary)
            }
        }
    }

    private func pageLabels(for item: BulkExportDraft.PageItem) -> some View {
        VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
            Text(item.documentName)
                .watakeType(.bodyEmphasis)
                .foregroundStyle(WatakeColor.text.primary)
                .lineLimit(1)
            Text(String(
                localized: "Page \(item.sourcePageIndex + 1) of \(item.sourceTotalPages)",
                comment: "Source page number in export list"
            ))
            .watakeType(.caption)
            .foregroundStyle(WatakeColor.text.secondary)
        }
    }

    private func includeToggle(for item: BulkExportDraft.PageItem) -> some View {
        Toggle(String(localized: "Include page", comment: "Toggle to include page in export"), isOn: Binding(
            get: { item.isIncluded },
            set: { _ in model.toggleInclusion(pageID: item.id) }
        ))
        .labelsHidden()
        .tint(WatakeColor.brand.primary)
    }

    private func announceMove(_ newIndex: Int?) {
        guard let newIndex else { return }
        AccessibilityNotification.Announcement(String(
            localized: "Moved to position \(newIndex + 1)",
            comment: "VoiceOver announcement after moving item"
        )).post()
    }

    private var createButton: some View {
        WatakeButton(
            String(localized: "Create PDF", comment: "Button to create PDF"),
            variant: .primary,
            isLoading: false
        ) {
            model.startExport()
        }
        .disabled(!(model.draft?.canExport ?? false))
    }

    private func errorMessage(for error: ExportUserError) -> String {
        switch error {
        case .noPages: String(localized: "No pages selected for export.", comment: "Error message when no pages are selected")
        case .pageUnavailable: String(
                localized: "A selected page is no longer available.",
                comment: "Error message when a page is unavailable"
            )
        case .renderFailed: String(localized: "Could not create the PDF.", comment: "Error message when PDF generation fails")
        case .storageFull: String(
                localized: "Not enough storage space to create the PDF.",
                comment: "Error message when device storage is full"
            )
        case .unknown: String(localized: "An unknown error occurred.", comment: "Generic error message")
        }
    }
}
