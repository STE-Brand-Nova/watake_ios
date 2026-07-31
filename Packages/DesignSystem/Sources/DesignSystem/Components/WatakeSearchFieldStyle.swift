import SwiftUI

/// A sunken search field with a leading magnifier glyph, per the `SearchField`
/// component in `Design.md`. Apply with `.textFieldStyle(.watakeSearch)`.
public struct WatakeSearchFieldStyle: TextFieldStyle {
    public init() {}

    // swiftlint:disable:next identifier_name
    public func _body(configuration: TextField<Self._Label>) -> some View {
        HStack(spacing: WatakeSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WatakeColor.text.secondary)
                .accessibilityHidden(true)
            configuration
                .font(WatakeTypography.body.font)
                .foregroundStyle(WatakeColor.text.primary)
        }
        .padding(.horizontal, WatakeSpacing.sm)
        .padding(.vertical, WatakeSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous)
                .fill(WatakeColor.surface.sunken)
        )
    }
}

extension TextFieldStyle where Self == WatakeSearchFieldStyle {
    /// The Watake sunken search field style.
    public static var watakeSearch: WatakeSearchFieldStyle {
        WatakeSearchFieldStyle()
    }
}
