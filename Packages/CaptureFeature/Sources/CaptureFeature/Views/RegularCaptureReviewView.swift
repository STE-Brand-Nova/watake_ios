import DesignSystem
import SwiftUI
import WatakeDomain

public struct RegularCaptureReviewView: View {
    @Bindable public var state: CaptureReviewState
    public let rectifier: (any DocumentRectifying)?
    public let onRetake: () -> Void

    public init(
        state: CaptureReviewState,
        rectifier: (any DocumentRectifying)? = nil,
        onRetake: @escaping () -> Void
    ) {
        self.state = state
        self.rectifier = rectifier
        self.onRetake = onRetake
    }

    public var body: some View {
        HStack(spacing: CaptureReviewLayoutPolicy.paneSpacing) {
            // Main Preview Pane (Left - Flexible)
            mainPreviewPane
                .frame(minWidth: CaptureReviewLayoutPolicy.mainPaneMinWidth, maxWidth: .infinity)

            // Trailing Panel (Right)
            trailingPanel
                .frame(width: CaptureReviewLayoutPolicy.trailingPanelWidth)
        }
        .padding(CaptureReviewLayoutPolicy.outerPaddingPerSide)
        .background(WatakeColor.surface.base)
    }

    private var mainPreviewPane: some View {
        VStack(spacing: WatakeSpacing.md) {
            ZStack {
                if let selectedPage = state.selectedPage, let platformImage = PlatformImage(data: selectedPage.displayData) {
                    platformImage.swiftUIImage
                        .resizable()
                        .scaledToFit()
                        .rotationEffect(.degrees(selectedPage.visualRotationDegrees))
                        .padding(WatakeSpacing.md)
                        .accessibilityLabel("Captured page \(state.selectedIndex + 1) of \(state.pages.count)")
                } else {
                    VStack(spacing: WatakeSpacing.sm) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 56))
                            .foregroundStyle(WatakeColor.text.secondary)
                        Text("No page selected")
                            .watakeType(.body)
                            .foregroundStyle(WatakeColor.text.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatakeColor.surface.raised)
            .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.lg))

            if let selectedPage = state.selectedPage, selectedPage.detectionUncertain {
                HStack(spacing: WatakeSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Review crop before saving")
                        .watakeType(.caption)
                }
                .foregroundStyle(WatakeColor.status.warning)
                .accessibilityLabel("Warning: Review crop before saving")
            }

            if let summary = state.autoAdjustmentSummary {
                autoAdjustmentFeedback(summary)
            }
        }
    }

    private var trailingPanel: some View {
        VStack(alignment: .leading, spacing: WatakeSpacing.lg) {
            Text("Document Pages")
                .watakeType(.title2)
                .foregroundStyle(WatakeColor.text.primary)

            // Vertical Page List
            ScrollView {
                VStack(spacing: WatakeSpacing.md) {
                    ForEach(Array(state.pages.enumerated()), id: \.element.id) { index, page in
                        pageRow(index: index, page: page)
                    }
                }
            }

            Divider()

            // Control Actions List
            VStack(spacing: WatakeSpacing.sm) {
                WatakeButton("Rotate Page", variant: .secondary) {
                    state.rotateSelectedPage(via: rectifier)
                }
                .disabled(state.selectedPage == nil || state.isSaving)
                .accessibilityLabel("Rotate page 90 degrees")

                WatakeButton("Adjust Corners", variant: .secondary) {
                    state.isEditingCrop = true
                }
                .disabled(state.selectedPage == nil || state.isSaving)
                .accessibilityLabel("Adjust crop corners")

                if state.uncertainPageCount > 0 {
                    WatakeButton(autoAdjustTitle, variant: .secondary) {
                        if let rectifier {
                            state.autoAdjustUncertainPages(via: rectifier)
                        }
                    }
                    .disabled(rectifier == nil || state.isSaving || state.isProcessing)
                    .accessibilityLabel("Automatically adjust \(state.uncertainPageCount) uncertain crop pages")
                }

                WatakeButton("Delete Page", variant: .secondary) {
                    state.deleteSelectedPage()
                }
                .disabled(state.selectedPage == nil || state.isSaving)
                .accessibilityLabel("Delete selected page")

                WatakeButton("Retake Capture", variant: .secondary) {
                    onRetake()
                }
                .disabled(state.isSaving)
                .accessibilityLabel("Retake capture flow")

                if state.isProcessing {
                    processingIndicator
                }

                WatakeButton("Save to Folder", variant: .primary) {
                    state.isShowingSaveDestination = true
                }
                .disabled(state.pages.isEmpty || state.isSaving || state.isProcessing)
                .accessibilityLabel(
                    state.isProcessing
                        ? "Save disabled while pages finish processing"
                        : "Save capture to folder"
                )
            }
        }
        .padding(WatakeSpacing.md)
        .background(WatakeColor.surface.raised)
        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.lg))
    }

    private var processingIndicator: some View {
        HStack(spacing: WatakeSpacing.xs) {
            ProgressView()
            Text("Finishing edits before save…")
                .watakeType(.caption)
        }
        .foregroundStyle(WatakeColor.text.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Finishing edits before save")
    }

    private func pageRow(index: Int, page: CaptureReviewPage) -> some View {
        let isSelected = index == state.selectedIndex
        let deleteLabel = "Delete page \(index + 1)"
        return HStack(spacing: WatakeSpacing.md) {
            PageThumbnailView(
                page: page,
                index: index,
                isSelected: isSelected,
                onSelect: { state.selectPage(at: index) },
                onDelete: nil
            )

            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Page \(index + 1)")
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)

                if page.rotationDegrees != 0 {
                    Text("Rotated \(page.rotationDegrees)°")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.brand.primary)
                }

                if page.detectionUncertain {
                    Text("Uncertain Crop")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.status.warning)
                } else if page.wasAutoCropAdjusted {
                    Text("Auto-adjusted safely")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.brand.primary)
                }
            }

            Spacer()

            Button(
                action: {
                    state.selectPage(at: index)
                    state.deleteSelectedPage()
                },
                label: {
                    Image(systemName: "trash")
                        .foregroundStyle(WatakeColor.status.danger)
                        .frame(width: 44, height: 44)
                }
            )
            .buttonStyle(.plain)
            .disabled(state.isSaving)
            .accessibilityLabel(deleteLabel)
        }
        .padding(WatakeSpacing.xs)
        .background(isSelected ? WatakeColor.surface.sunken : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md))
    }

    private var autoAdjustTitle: String {
        let count = state.uncertainPageCount
        return count == 1 ? "Auto-adjust 1 page" : "Auto-adjust \(count) pages"
    }

    private func autoAdjustmentFeedback(_ summary: AutoAdjustmentSummary) -> some View {
        HStack(spacing: WatakeSpacing.xs) {
            Image(systemName: summary.needsManualReview ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(summary.message)
                .watakeType(.caption)
        }
        .foregroundStyle(summary.needsManualReview ? WatakeColor.status.warning : WatakeColor.brand.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.message)
    }
}
