import CoreGraphics
import DesignSystem

/// Single source of truth for the Capture Review two-pane breakpoint.
///
/// These constants are what `RegularCaptureReviewView` actually renders
/// (main pane minimum width, trailing panel width, pane spacing, outer
/// padding) per the "Capture Preview" two-pane layout in `RESPONSIVE.md`.
/// `twoPaneMinWidth` is derived from them so the breakpoint can never drift
/// below what the layout needs without clipping, overlap, or overflow.
public enum CaptureReviewLayoutPolicy {
    /// Matches `RegularCaptureReviewView.mainPreviewPane`'s `minWidth`.
    public static let mainPaneMinWidth: CGFloat = 480
    /// Matches `RegularCaptureReviewView.trailingPanel`'s fixed `width`.
    public static let trailingPanelWidth: CGFloat = 320
    /// Matches the `HStack` spacing between the two panes.
    public static let paneSpacing: CGFloat = WatakeSpacing.lg
    /// Matches the outer padding applied to each side of the two-pane `HStack`.
    public static let outerPaddingPerSide: CGFloat = WatakeSpacing.lg

    /// The minimum container width the two-pane layout needs to render both
    /// panes at their minimum sizes without clipping, overlap, or horizontal
    /// overflow. Below this width, callers must use the compact layout.
    public static var twoPaneMinWidth: CGFloat {
        mainPaneMinWidth + trailingPanelWidth + paneSpacing + (outerPaddingPerSide * 2)
    }

    /// Whether a container of the given width fits the two-pane layout.
    public static func usesTwoPane(forWidth width: CGFloat) -> Bool {
        width >= twoPaneMinWidth
    }
}
