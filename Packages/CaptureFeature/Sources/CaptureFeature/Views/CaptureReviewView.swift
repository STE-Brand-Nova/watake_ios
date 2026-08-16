import DesignSystem
import SwiftUI
import WatakeDomain

public struct CaptureReviewView: View {
    public static let twoPaneMinWidth: CGFloat = CaptureReviewLayoutPolicy.twoPaneMinWidth

    @Bindable public var state: CaptureReviewState
    public let folderProvider: any CaptureFolderProviding
    public let saver: any CaptureSaving
    public let rectifier: (any DocumentRectifying)?
    public let onRetake: () -> Void
    public let onSaved: (UUID) -> Void
    @FocusState private var isReviewSurfaceFocused: Bool

    public init(
        state: CaptureReviewState,
        folderProvider: any CaptureFolderProviding,
        saver: any CaptureSaving,
        rectifier: (any DocumentRectifying)? = nil,
        onRetake: @escaping () -> Void,
        onSaved: @escaping (UUID) -> Void
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
            let useTwoPane = CaptureReviewLayoutPolicy.usesTwoPane(forWidth: geometry.size.width)

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
            // `onKeyPress` only fires while the modified view or a descendant
            // has focus; ordinary touch navigation never assigns focus, so
            // without this the shortcuts below would never fire on iPad.
            // Claim focus once on appear and reclaim it whenever the crop
            // editor/save sheet/save-in-flight state clears, so this never
            // steals focus away while one of those owns it.
            .focusable()
            .focused($isReviewSurfaceFocused)
            .onAppear { isReviewSurfaceFocused = true }
            .onChange(of: canUseReviewShortcuts) { _, canUse in
                if canUse {
                    isReviewSurfaceFocused = true
                }
            }
            .sheet(isPresented: $state.isEditingCrop) {
                CropEditorView(state: state, rectifier: rectifier)
            }
            .sheet(isPresented: $state.isShowingSaveDestination) {
                saveDestinationSheet(forWidth: geometry.size.width)
            }
            // Guarded against the crop editor and save-destination sheets so
            // these shortcuts never fire behind a modal's text entry.
            .onKeyPress(.rightArrow) { selectAdjacentPage(offset: 1) }
            .onKeyPress(.leftArrow) { selectAdjacentPage(offset: -1) }
            .onKeyPress("r") {
                guard canUseReviewShortcuts, state.selectedPage != nil else { return .ignored }
                state.rotateSelectedPage(via: rectifier)
                return .handled
            }
        }
    }

    private var canUseReviewShortcuts: Bool {
        !state.isEditingCrop && !state.isShowingSaveDestination && !state.isSaving
    }

    private func selectAdjacentPage(offset: Int) -> KeyPress.Result {
        guard canUseReviewShortcuts else { return .ignored }
        let target = state.selectedIndex + offset
        guard state.pages.indices.contains(target) else { return .ignored }
        state.selectPage(at: target)
        return .handled
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
