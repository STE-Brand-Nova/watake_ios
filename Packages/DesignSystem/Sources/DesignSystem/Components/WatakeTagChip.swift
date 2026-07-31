import SwiftUI

/// A small pill label used for tags and active presets. Accepts a semantic token
/// color; callers pass a `WatakeColor` value (e.g. `WatakeColor.status.warning`),
/// never a raw color.
///
/// The tint colors only the background and border. The label always uses
/// `WatakeColor.text.primary` so text contrast stays ≥ 4.5:1 regardless of the
/// tint (a low-contrast tint used as the label color would fail WCAG).
public struct WatakeTagChip: View {
    private let label: String
    private let color: Color
    private let accessibilityIdentifier: String?

    /// - Parameters:
    ///   - label: Chip text.
    ///   - color: Tint token for background/border; defaults to the brand color.
    ///   - accessibilityIdentifier: Optional caller-supplied identifier. Features
    ///     derive a unique identifier from their domain model; the component does
    ///     not impose a shared constant on every instance.
    public init(
        _ label: String,
        color: Color = WatakeColor.brand.primary,
        accessibilityIdentifier: String? = nil
    ) {
        self.label = label
        self.color = color
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        Text(label)
            .watakeType(.caption)
            .foregroundStyle(WatakeColor.text.primary)
            .padding(.horizontal, WatakeSpacing.sm)
            .padding(.vertical, WatakeSpacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.24), lineWidth: 1)
            )
            .watakeAccessibilityIdentifier(accessibilityIdentifier)
    }
}
