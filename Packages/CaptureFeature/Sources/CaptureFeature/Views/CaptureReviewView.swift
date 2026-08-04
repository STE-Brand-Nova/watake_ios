import DesignSystem
import SwiftUI
import WatakeDomain

public struct CaptureReviewView: View {
    public static let twoPaneMinWidth: CGFloat = 872

    @Bindable public var state: CaptureReviewState
    public let folderProvider: any CaptureFolderProviding
    public let saver: any CaptureSaving
    public let rectifier: (any DocumentRectifying)?
    public let onRetake: () -> Void
    public let onSaved: () -> Void

    public init(
        state: CaptureReviewState,
        folderProvider: any CaptureFolderProviding,
        saver: any CaptureSaving,
        rectifier: (any DocumentRectifying)? = nil,
        onRetake: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.state = state
        self.folderProvider = folderProvider
        self.saver = saver
        self.rectifier = rectifier
        self.onRetake = onRetake
        self.onSaved = onSaved
    }

    public var body: some View {
        GeometryReader { geometry in
            let useTwoPane = geometry.size.width >= Self.twoPaneMinWidth

            Group {
                if useTwoPane {
                    RegularCaptureReviewView(
                        state: state,
                        rectifier: rectifier,
                        onRetake: onRetake
                    )
                } else {
                    CompactCaptureReviewView(
                        state: state,
                        rectifier: rectifier,
                        onRetake: onRetake
                    )
                }
            }
            .sheet(isPresented: $state.isEditingCrop) {
                CropEditorView(state: state, rectifier: rectifier)
            }
            .sheet(isPresented: $state.isShowingSaveDestination) {
                saveDestinationSheet(forWidth: geometry.size.width)
            }
        }
    }

    @ViewBuilder
    private func saveDestinationSheet(forWidth width: CGFloat) -> some View {
        let isRegularOrExpanded = width >= Self.twoPaneMinWidth

        SaveDestinationView(
            state: state,
            folderProvider: folderProvider,
            saver: saver,
            onSaved: onSaved
        )
        .frame(maxWidth: isRegularOrExpanded ? 560 : .infinity)
        .presentationDetents(isRegularOrExpanded ? [.large] : [.medium, .large])
    }
}
