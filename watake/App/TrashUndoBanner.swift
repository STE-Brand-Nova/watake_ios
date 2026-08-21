import DesignSystem
import SwiftUI

struct TrashUndoBanner: View {
    let undo: () -> Void

    var body: some View {
        HStack(spacing: WatakeSpacing.md) {
            Text("Moved to Trash")
                .watakeType(.bodyEmphasis)
                .foregroundStyle(WatakeColor.text.primary)
            Spacer(minLength: 0)
            Button("Undo", action: undo)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Undo move to Trash")
                .accessibilityHint("Restores the most recently deleted item")
        }
        .padding(.horizontal, WatakeSpacing.md)
        .background(WatakeColor.surface.raised)
        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: WatakeRadius.md)
                .stroke(WatakeColor.border.subtle, lineWidth: 1)
        }
        .padding(.horizontal, WatakeSpacing.md)
        .accessibilityElement(children: .contain)
    }
}
