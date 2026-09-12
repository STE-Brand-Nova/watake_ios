#if canImport(UIKit)
    import DesignSystem
    import SwiftUI

    struct HighlightContextToolbar: View {
        @Binding var isAdjusting: Bool
        let appearsBelow: Bool
        let delete: () -> Void
        let showMore: () -> Void

        var body: some View {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    toolbarButton(icon: "trash", label: "Delete highlight", role: .destructive, action: delete)
                    toolbarButton(
                        icon: "arrow.up.left.and.arrow.down.right",
                        label: "Adjust or move highlight",
                        isActive: isAdjusting,
                        action: { isAdjusting.toggle() }
                    )
                    toolbarButton(icon: "ellipsis", label: "More highlight options", action: showMore)
                }
                .padding(.horizontal, 4)
                .background(WatakeColor.surface.raised)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(WatakeColor.border.strong, lineWidth: 1))
                .position(x: proxy.size.width / 2, y: appearsBelow ? proxy.size.height + 28 : -28)
            }
        }

        private func toolbarButton(
            icon: String,
            label: String,
            role: ButtonRole? = nil,
            isActive: Bool = false,
            action: @escaping () -> Void
        ) -> some View {
            Button(role: role, action: action) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(
                        role == .destructive
                            ? WatakeColor.status.danger
                            : (isActive ? WatakeColor.brand.primary : WatakeColor.text.primary)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
    }
#endif
