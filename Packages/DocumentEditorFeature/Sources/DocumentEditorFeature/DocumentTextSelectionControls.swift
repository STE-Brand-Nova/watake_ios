#if canImport(UIKit)
    import DesignSystem
    import SwiftUI

    struct TextSelectionButton: View {
        let icon: String
        let label: String
        let role: ButtonRole?
        let pageShortEdge: CGFloat
        let action: () -> Void

        init(
            icon: String,
            label: String,
            role: ButtonRole? = nil,
            pageShortEdge: CGFloat,
            action: @escaping () -> Void
        ) {
            self.icon = icon
            self.label = label
            self.role = role
            self.pageShortEdge = pageShortEdge
            self.action = action
        }

        var body: some View {
            Button(role: role, action: action) {
                TextSelectionControl(icon: icon, role: role, pageShortEdge: pageShortEdge)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    }

    struct TextSelectionHandle: View {
        let icon: String
        let label: String
        let pageShortEdge: CGFloat

        var body: some View {
            TextSelectionControl(icon: icon, pageShortEdge: pageShortEdge)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
        }
    }

    private struct TextSelectionControl: View {
        let icon: String
        var role: ButtonRole?
        let pageShortEdge: CGFloat

        var body: some View {
            let diameter = min(max(pageShortEdge * 0.075, 26), 32)
            Image(systemName: icon)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .frame(width: diameter, height: diameter)
                .foregroundStyle(role == .destructive ? WatakeColor.status.danger : WatakeColor.brand.primary)
                .background(WatakeColor.surface.raised)
                .clipShape(Circle())
                .overlay(Circle().stroke(WatakeColor.border.strong, lineWidth: 1))
        }
    }
#endif
