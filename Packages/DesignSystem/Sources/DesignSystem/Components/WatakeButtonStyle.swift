import SwiftUI

/// Variants for `WatakeButtonStyle`, mapped to `Design.md` button components.
public enum WatakeButtonVariant: Equatable {
    case primary
    case secondary
    case destructive
    case text
    case icon
}

// MARK: - Appearance resolution (pure, testable)

/// Resolved semantic roles for a button in a given interaction state.
///
/// Kept as roles rather than `Color` so the state machine is unit-testable
/// without comparing rendered colors.
struct WatakeButtonAppearance: Equatable {
    enum Fill: Equatable {
        case brandPrimary, brandPressed, brandDisabled
        case danger, dangerPressed, dangerDisabled
        case surfaceBase, surfaceSunken
        case clear
    }

    enum Foreground: Equatable {
        case onPrimary, onDanger
        case textPrimary, textDisabled
        case brandPrimary, brandPressed
    }

    enum Border: Equatable {
        case none, subtle, strong
    }

    var fill: Fill
    var foreground: Foreground
    var border: Border

    /// The button state machine. `isPressed` is ignored when disabled.
    static func resolve(
        variant: WatakeButtonVariant,
        isEnabled: Bool,
        isPressed: Bool
    ) -> WatakeButtonAppearance {
        switch variant {
        case .primary, .icon:
            if !isEnabled {
                return .init(fill: .brandDisabled, foreground: .onPrimary, border: .none)
            }
            return .init(
                fill: isPressed ? .brandPressed : .brandPrimary,
                foreground: .onPrimary,
                border: .none
            )
        case .secondary:
            if !isEnabled {
                return .init(fill: .surfaceBase, foreground: .textDisabled, border: .subtle)
            }
            return .init(
                fill: isPressed ? .surfaceSunken : .surfaceBase,
                foreground: .textPrimary,
                border: .strong
            )
        case .destructive:
            if !isEnabled {
                return .init(fill: .dangerDisabled, foreground: .onDanger, border: .none)
            }
            return .init(
                fill: isPressed ? .dangerPressed : .danger,
                foreground: .onDanger,
                border: .none
            )
        case .text:
            if !isEnabled {
                return .init(fill: .clear, foreground: .textDisabled, border: .none)
            }
            return .init(
                fill: .clear,
                foreground: isPressed ? .brandPressed : .brandPrimary,
                border: .none
            )
        }
    }
}

extension WatakeButtonAppearance.Fill {
    var color: Color {
        switch self {
        case .brandPrimary: WatakeColor.brand.primary
        case .brandPressed: WatakeColor.brand.primaryPressed
        case .brandDisabled: WatakeColor.brand.primaryDisabled
        case .danger: WatakeColor.status.danger
        case .dangerPressed: WatakeColor.status.danger.opacity(0.85)
        case .dangerDisabled: WatakeColor.status.danger.opacity(0.4)
        case .surfaceBase: WatakeColor.surface.base
        case .surfaceSunken: WatakeColor.surface.sunken
        case .clear: Color.clear
        }
    }
}

extension WatakeButtonAppearance.Foreground {
    var color: Color {
        switch self {
        case .onPrimary: WatakeColor.text.onPrimary
        case .onDanger: WatakeColor.text.onDanger
        case .textPrimary: WatakeColor.text.primary
        case .textDisabled: WatakeColor.text.disabled
        case .brandPrimary: WatakeColor.brand.primary
        case .brandPressed: WatakeColor.brand.primaryPressed
        }
    }
}

extension WatakeButtonAppearance.Border {
    var color: Color {
        switch self {
        case .none: Color.clear
        case .subtle: WatakeColor.border.subtle
        case .strong: WatakeColor.border.strong
        }
    }

    var width: CGFloat {
        self == .none ? 0 : 1
    }
}

// MARK: - ButtonStyle

/// The shared Watake button style. Enforces a 44×44pt minimum target, honors
/// Reduce Motion, and shows a spinner in place of the label while loading.
///
/// Prefer the `.watake(_:loading:)` factory. For icon-only buttons use
/// `WatakeIconButton`, which requires an accessibility label.
public struct WatakeButtonStyle: ButtonStyle {
    private let variant: WatakeButtonVariant
    private let isLoading: Bool

    public init(variant: WatakeButtonVariant, isLoading: Bool = false) {
        self.variant = variant
        self.isLoading = isLoading
    }

    /// A loading button is non-interactive: taps are blocked so a slow action
    /// (save, export) cannot be triggered twice.
    static func acceptsTaps(isLoading: Bool) -> Bool {
        !isLoading
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyleBody(variant: variant, isLoading: isLoading, configuration: configuration)
    }

    private struct StyleBody: View {
        let variant: WatakeButtonVariant
        let isLoading: Bool
        let configuration: Configuration

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var appearance: WatakeButtonAppearance {
            .resolve(variant: variant, isEnabled: isEnabled, isPressed: configuration.isPressed)
        }

        private var isIcon: Bool {
            variant == .icon
        }

        var body: some View {
            let radius = WatakeRadius.md
            return configuration.label
                .watakeType(.bodyEmphasis)
                .opacity(isLoading ? 0 : 1)
                .padding(.horizontal, isIcon ? 0 : WatakeSpacing.md)
                .padding(.vertical, isIcon ? 0 : WatakeSpacing.sm)
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(appearance.foreground.color)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(appearance.fill.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(appearance.border.color, lineWidth: appearance.border.width)
                )
                .overlay {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(appearance.foreground.color)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .opacity(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
                // Block taps while loading so a slow action cannot be double-fired,
                // even when a caller applies the style directly.
                .allowsHitTesting(WatakeButtonStyle.acceptsTaps(isLoading: isLoading))
        }
    }
}

extension ButtonStyle where Self == WatakeButtonStyle {
    /// A Watake button style. Pass `loading: true` to swap the label for a spinner.
    public static func watake(_ variant: WatakeButtonVariant, loading: Bool = false) -> WatakeButtonStyle {
        WatakeButtonStyle(variant: variant, isLoading: loading)
    }
}
