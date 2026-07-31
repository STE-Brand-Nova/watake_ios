import SwiftUI

/// Surface elevation for `WatakeCard`.
public enum WatakeSurface {
    /// Raised above the base canvas (folder cards, list rows).
    case raised
    /// Recessed into the canvas (wells, inline previews).
    case sunken

    var background: Color {
        switch self {
        case .raised: WatakeColor.surface.raised
        case .sunken: WatakeColor.surface.sunken
        }
    }
}

/// A semantic surface container: fill, hairline border, and radius. Uses border
/// separation instead of heavy shadows so it reads correctly in Dark mode.
public struct WatakeCard<Content: View>: View {
    private let surface: WatakeSurface
    private let content: Content

    public init(surface: WatakeSurface = .raised, @ViewBuilder content: () -> Content) {
        self.surface = surface
        self.content = content()
    }

    public var body: some View {
        content
            .padding(WatakeSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: WatakeRadius.lg, style: .continuous)
                    .fill(surface.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WatakeRadius.lg, style: .continuous)
                    .strokeBorder(WatakeColor.border.subtle, lineWidth: 1)
            )
    }
}
