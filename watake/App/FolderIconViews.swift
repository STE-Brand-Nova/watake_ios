import DesignSystem
import SwiftUI
import WatakeDomain

struct FolderIconDefinition: Identifiable, Equatable {
    let id: String
    let title: String

    var assetName: String {
        "FolderIcon-\(id)"
    }

    static let all: [FolderIconDefinition] = [
        .init(id: "folder", title: "Folder"),
        .init(id: "receipt", title: "Receipts"),
        .init(id: "briefcase", title: "Work"),
        .init(id: "house", title: "Home"),
        .init(id: "book-open", title: "Books"),
        .init(id: "graduation-cap", title: "Education"),
        .init(id: "car", title: "Vehicle"),
        .init(id: "airplane-tilt", title: "Travel"),
        .init(id: "heart", title: "Health"),
        .init(id: "shield-check", title: "Important"),
        .init(id: "archive", title: "Archive"),
        .init(id: "file-text", title: "Documents")
    ]

    static func resolve(_ id: String) -> FolderIconDefinition {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

struct FolderIconView: View {
    let iconId: String
    let color: Color

    var body: some View {
        Image(FolderIconDefinition.resolve(iconId).assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

struct FolderIconPicker: View {
    @Binding var selection: String
    let color: Color

    private let columns = [
        GridItem(.adaptive(minimum: WatakeSpacing.huge + WatakeSpacing.md), spacing: WatakeSpacing.sm)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: WatakeSpacing.sm) {
            ForEach(FolderIconDefinition.all) { icon in
                Button {
                    selection = icon.id
                } label: {
                    VStack(spacing: WatakeSpacing.xs) {
                        FolderIconView(iconId: icon.id, color: color)
                            .frame(width: WatakeSpacing.xl, height: WatakeSpacing.xl)

                        Text(icon.title)
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: WatakeSpacing.huge)
                    .padding(.horizontal, WatakeSpacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous)
                            .fill(WatakeColor.surface.sunken)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous)
                            .strokeBorder(
                                selection == icon.id ? WatakeColor.brand.primary : WatakeColor.border.subtle,
                                lineWidth: selection == icon.id ? 2 : 1
                            )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon.title)
                .accessibilityAddTraits(selection == icon.id ? [.isSelected] : [])
                .accessibilityHint(selection == icon.id ? "Selected" : "Selects this folder icon")
            }
        }
    }
}

struct FolderAppearancePreview: View {
    let name: String
    let iconId: String
    let color: Color

    var body: some View {
        HStack(spacing: WatakeSpacing.sm) {
            FolderIconView(iconId: iconId, color: color)
                .frame(width: WatakeSpacing.xxl, height: WatakeSpacing.xxl)
            VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
                Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Folder name" : name)
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                    .lineLimit(2)
                Text(FolderIconDefinition.resolve(iconId).title)
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, WatakeSpacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
