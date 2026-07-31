import SwiftUI

/// A titled Watake button. Prefer this over applying `WatakeButtonStyle`
/// directly: it renders a spinner while loading **and** disables the button so
/// the action cannot be triggered twice (e.g. a duplicate save or export).
///
/// For icon-only buttons use `WatakeIconButton`, which requires an
/// accessibility label.
public struct WatakeButton: View {
    private let title: String
    private let variant: WatakeButtonVariant
    private let isLoading: Bool
    private let accessibilityIdentifier: String?
    private let action: () -> Void

    /// - Parameters:
    ///   - title: Button label.
    ///   - variant: Visual/semantic variant (`.primary` by default).
    ///   - isLoading: Shows a spinner and disables the button while true.
    ///   - accessibilityIdentifier: Optional caller-supplied identifier.
    ///   - action: Tap handler.
    public init(
        _ title: String,
        variant: WatakeButtonVariant = .primary,
        isLoading: Bool = false,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.isLoading = isLoading
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        Button(title, action: action)
            .buttonStyle(.watake(variant, loading: isLoading))
            .disabled(isLoading)
            .watakeAccessibilityIdentifier(accessibilityIdentifier)
    }
}
