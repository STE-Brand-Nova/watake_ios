import DesignSystem
import SwiftUI
import WatakeDomain

public struct CompactCaptureReviewView: View {
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
        VStack(spacing: WatakeSpacing.md) {
            // Main Document Preview
            mainPreviewArea

            // Crop Warning Badge
            if let selectedPage = state.selectedPage, selectedPage.detectionUncertain {
                HStack(spacing: WatakeSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Review crop before saving")
                        .watakeType(.caption)
                }
                .foregroundStyle(WatakeColor.status.warning)
                .padding(.horizontal, WatakeSpacing.md)
                .accessibilityLabel("Warning: Review crop before saving")
            }

            // Horizontal Page-Thumbnail Strip
            thumbnailStrip

            // Bottom Action Toolbar
            bottomToolbar
        }
        .padding(.vertical, WatakeSpacing.md)
        .background(WatakeColor.surface.base)
    }

    private var mainPreviewArea: some View {
        ZStack {
            if let selectedPage = state.selectedPage, let platformImage = PlatformImage(data: selectedPage.displayData) {
                platformImage.swiftUIImage
                    .resizable()
                    .scaledToFit()
                    .rotationEffect(.degrees(selectedPage.visualRotationDegrees))
                    .padding(.horizontal, WatakeSpacing.md)
                    .accessibilityLabel("Captured page \(state.selectedIndex + 1) of \(state.pages.count)")
            } else {
                VStack(spacing: WatakeSpacing.sm) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(WatakeColor.text.secondary)
                    Text("No page selected")
                        .watakeType(.body)
                        .foregroundStyle(WatakeColor.text.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WatakeSpacing.md) {
                ForEach(Array(state.pages.enumerated()), id: \.element.id) { index, page in
                    PageThumbnailView(
                        page: page,
                        index: index,
                        isSelected: index == state.selectedIndex,
                        onSelect: { state.selectPage(at: index) },
                        onDelete: state.isSaving ? nil : { state.selectPage(at: index)
                            state.deleteSelectedPage()
                        }
                    )
                }
            }
            .padding(.horizontal, WatakeSpacing.md)
        }
        .frame(height: 120)
    }

    private var processingIndicator: some View {
        HStack(spacing: WatakeSpacing.xs) {
            ProgressView()
            Text("Finishing edits before save…")
                .watakeType(.caption)
        }
        .foregroundStyle(WatakeColor.text.secondary)
        .padding(.horizontal, WatakeSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Finishing edits before save")
    }

    private var bottomToolbar: some View {
        VStack(spacing: WatakeSpacing.sm) {
            if state.isProcessing {
                processingIndicator
            }

            HStack(spacing: WatakeSpacing.sm) {
                WatakeButton("Retake", variant: .secondary) {
                    onRetake()
                }
                .disabled(state.isSaving)
                .accessibilityLabel("Retake all pages")

                WatakeButton("Rotate", variant: .secondary) {
                    state.rotateSelectedPage(via: rectifier)
                }
                .disabled(state.selectedPage == nil || state.isSaving)
                .accessibilityLabel("Rotate page 90 degrees")

                WatakeButton("Adjust corners", variant: .secondary) {
                    state.isEditingCrop = true
                }
                .disabled(state.selectedPage == nil || state.isSaving)
                .accessibilityLabel("Adjust crop corners")
            }

            HStack(spacing: WatakeSpacing.sm) {
                WatakeButton("Delete page", variant: .secondary) {
                    state.deleteSelectedPage()
                }
                .disabled(state.selectedPage == nil || state.isSaving)
                .accessibilityLabel("Delete current page")

                WatakeButton("Save to folder", variant: .primary) {
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
        .padding(.horizontal, WatakeSpacing.md)
    }
}
