#if canImport(UIKit)
    import DesignSystem
    import SwiftUI

    struct HighlightContextToolbar<MoveGesture: Gesture>: View {
        @Binding var isAdjusting: Bool
        let appearsBelow: Bool
        let moveGesture: MoveGesture
        let delete: () -> Void
        let showMore: () -> Void

        var body: some View {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    toolbarButton(icon: "trash", label: "Delete highlight", role: .destructive, action: delete)
                    moveHandle
                    toolbarButton(icon: "ellipsis", label: "More highlight options", action: showMore)
                }
                .padding(.horizontal, 4)
                .background(WatakeColor.surface.raised)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(WatakeColor.border.strong, lineWidth: 1))
                .position(x: proxy.size.width / 2, y: appearsBelow ? proxy.size.height + 28 : -28)
            }
        }

        private var moveHandle: some View {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(isAdjusting ? WatakeColor.brand.primary : WatakeColor.text.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture { isAdjusting.toggle() }
                .highPriorityGesture(moveGesture, including: .all)
                .accessibilityElement()
                .accessibilityLabel("Adjust or move highlight")
                .accessibilityHint("Drag this control to move the highlight, or tap then drag the highlight.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(isAdjusting ? .isSelected : [])
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
