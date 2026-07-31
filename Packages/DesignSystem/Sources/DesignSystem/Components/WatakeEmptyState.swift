import SwiftUI

/// A centered empty-state placeholder: SF Symbol, title, message, and an
/// optional action button. Reflows for Dynamic Type and stays restrained (no
/// promotional dashboard) per `RESPONSIVE.md`.
public struct WatakeEmptyState: View {
    private let systemImage: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let actionAccessibilityIdentifier: String?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - systemImage: SF Symbol name for the graphic.
    ///   - title: Short headline.
    ///   - message: Supporting subtext.
    ///   - actionTitle: Optional button label; omit for a passive state.
    ///   - actionAccessibilityIdentifier: Optional caller-supplied identifier for
    ///     the action button.
    ///   - action: Optional button handler.
    public init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        actionAccessibilityIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionAccessibilityIdentifier = actionAccessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        VStack(spacing: WatakeSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(WatakeColor.text.secondary)
                .accessibilityHidden(true)

            VStack(spacing: WatakeSpacing.xs) {
                Text(title)
                    .watakeType(.title2)
                    .foregroundStyle(WatakeColor.text.primary)
                Text(message)
                    .watakeType(.body)
                    .foregroundStyle(WatakeColor.text.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.watake(.primary))
                    .watakeAccessibilityIdentifier(actionAccessibilityIdentifier)
            }
        }
        .frame(maxWidth: 320)
        .padding(WatakeSpacing.xl)
    }
}
