import SwiftUI

/// An icon-only button that *requires* an accessibility label at the call site,
/// so VoiceOver always has a description. Renders with the `.icon` button style
/// and a 44×44pt minimum target.
public struct WatakeIconButton: View {
    private let systemImage: String
    private let accessibilityLabel: Text
    private let isLoading: Bool
    private let accessibilityIdentifier: String?
    private let action: () -> Void

    /// - Parameters:
    ///   - systemImage: SF Symbol name.
    ///   - accessibilityLabel: Required spoken description (icon has no text).
    ///   - isLoading: Replaces the glyph with a spinner and blocks taps.
    ///   - accessibilityIdentifier: Optional caller-supplied identifier; features
    ///     derive a unique one per instance.
    public init(
        systemImage: String,
        accessibilityLabel: Text,
        isLoading: Bool = false,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.isLoading = isLoading
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.medium)
        }
        .buttonStyle(.watake(.icon, loading: isLoading))
        .disabled(isLoading)
        .accessibilityLabel(accessibilityLabel)
        .watakeAccessibilityIdentifier(accessibilityIdentifier)
    }
}
