import SwiftUI

/// Filled-circle emphasis badge from `Design.md` §9.8: used inline, in place
/// of a plain icon, to mark a single screen's most prominent action
/// (Capture) without adding a second, duplicate control.
///
/// Uses a hairline border instead of a heavy shadow so it reads correctly in
/// Dark mode, matching `WatakeCard`'s surface-separation approach.
public struct WatakeFAB: View {
    private let systemImage: String
    private let accessibilityLabel: Text
    private let size: CGFloat
    private let action: () -> Void

    /// - Parameters:
    ///   - systemImage: SF Symbol name.
    ///   - accessibilityLabel: Spoken description (icon has no text).
    ///   - size: Circle diameter. Defaults to the 52pt in-bar badge size.
    public init(
        systemImage: String,
        accessibilityLabel: Text,
        size: CGFloat = 52,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(WatakeColor.text.onPrimary)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .background(Circle().fill(WatakeColor.brand.primary))
        .overlay(Circle().strokeBorder(WatakeColor.border.subtle, lineWidth: 1))
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
    }
}
