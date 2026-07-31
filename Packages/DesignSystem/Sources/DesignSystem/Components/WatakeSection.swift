import SwiftUI

/// A titled content group with an optional trailing action, using semantic
/// spacing. Composes lists, forms, and inspector groupings.
public struct WatakeSection<Content: View>: View {
    private let title: String
    private let actionTitle: String?
    private let actionAccessibilityIdentifier: String?
    private let action: (() -> Void)?
    private let content: Content

    /// - Parameters:
    ///   - title: Section header text.
    ///   - actionTitle: Optional trailing text-button label.
    ///   - actionAccessibilityIdentifier: Optional caller-supplied identifier for
    ///     the trailing action.
    ///   - action: Optional trailing-button handler.
    ///   - content: Section body.
    public init(
        _ title: String,
        actionTitle: String? = nil,
        actionAccessibilityIdentifier: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.actionAccessibilityIdentifier = actionAccessibilityIdentifier
        self.action = action
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: WatakeSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .watakeType(.overline)
                    .foregroundStyle(WatakeColor.text.secondary)
                Spacer(minLength: WatakeSpacing.sm)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.watake(.text))
                        .watakeAccessibilityIdentifier(actionAccessibilityIdentifier)
                }
            }
            content
        }
    }
}
