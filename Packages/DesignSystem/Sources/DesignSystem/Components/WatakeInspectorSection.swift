import SwiftUI

/// An expandable container for advanced controls (the `InspectorSection`
/// component in `Design.md`), built on `DisclosureGroup`. Honors Reduce Motion
/// via SwiftUI's default disclosure animation handling.
public struct WatakeInspectorSection<Content: View>: View {
    private let title: String
    @Binding private var isExpanded: Bool
    private let accessibilityIdentifier: String?
    private let content: Content

    /// - Parameters:
    ///   - title: Header label.
    ///   - isExpanded: Expansion binding owned by the caller.
    ///   - accessibilityIdentifier: Optional caller-supplied identifier; features
    ///     derive a unique one per instance.
    ///   - content: Advanced controls revealed when expanded.
    public init(
        _ title: String,
        isExpanded: Binding<Bool>,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _isExpanded = isExpanded
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, WatakeSpacing.xs)
        } label: {
            Text(title)
                .watakeType(.bodyEmphasis)
                .foregroundStyle(WatakeColor.text.primary)
        }
        .tint(WatakeColor.brand.primary)
        .watakeAccessibilityIdentifier(accessibilityIdentifier)
    }
}
