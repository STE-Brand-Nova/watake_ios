import ArchiveServices
import DesignSystem
import SwiftUI
import WatakeDomain

/// Resolves a document's saved tag IDs to their current label/color and
/// renders up to 3 chips plus a `+N` overflow chip, so a renamed or
/// recolored tag stays correct everywhere it's displayed.
struct DocumentTagChips: View {
    @Bindable var store: LibraryStore
    let tagIds: [UUID]

    private var resolvedTags: [Tag] {
        let byID = Dictionary(uniqueKeysWithValues: store.tags.map { ($0.id, $0) })
        return tagIds.compactMap { byID[$0] }
    }

    var body: some View {
        let visible = resolvedTags.prefix(3)
        let overflow = resolvedTags.count - visible.count
        TagFlowLayout(spacing: WatakeSpacing.xxs) {
            ForEach(visible) { tag in
                WatakeTagChip(tag.label, color: tagColor(for: tag.colorHex), showsColorDot: true)
            }
            if overflow > 0 {
                WatakeTagChip("+\(overflow)")
            }
        }
    }
}

/// Wraps chip content onto multiple lines instead of overflowing off-screen,
/// so up to three 50-character tag labels stay readable at large Dynamic
/// Type sizes or in narrow grid cells.
struct TagFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var originX = bounds.minX
        var originY = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if originX > bounds.minX, originX - bounds.minX + spacing + size.width > maxWidth {
                originX = bounds.minX
                originY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: originX, y: originY),
                proposal: ProposedViewSize(width: min(size.width, maxWidth), height: size.height)
            )
            originX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// In-session, single-tag filter for a folder's document browser. Offers
/// "All documents" plus every tag; the selected chip shows a checkmark so
/// color is never the sole selection cue.
struct TagFilterRow: View {
    @Bindable var store: LibraryStore

    var body: some View {
        if !store.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WatakeSpacing.sm) {
                    filterChip(label: "All documents", isSelected: store.selectedTagFilterID == nil) {
                        store.setTagFilter(nil)
                    }
                    ForEach(store.tags) { tag in
                        filterChip(
                            label: tag.label,
                            color: tagColor(for: tag.colorHex),
                            isSelected: store.selectedTagFilterID == tag.id
                        ) {
                            store.setTagFilter(store.selectedTagFilterID == tag.id ? nil : tag)
                        }
                    }
                }
                .padding(.horizontal, WatakeSpacing.md)
                .padding(.vertical, WatakeSpacing.sm)
            }
        }
    }

    private func filterChip(
        label: String,
        color: Color = WatakeColor.brand.primary,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: WatakeSpacing.xxs) {
                if isSelected {
                    Image(systemName: "checkmark")
                }
                Text(label)
            }
            .watakeType(.caption)
            .foregroundStyle(WatakeColor.text.primary)
            .padding(.horizontal, WatakeSpacing.sm)
            .padding(.vertical, WatakeSpacing.xxs)
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(isSelected ? 0.24 : 0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(isSelected ? 0.6 : 0.24), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Filters documents by this tag")
    }
}

/// Label input plus the fixed 12-swatch picker, shared by tag creation and
/// editing so both flows use identical validation and controls.
struct TagForm: View {
    @Binding var label: String
    @Binding var color: String
    var labelPlaceholder = "Tag label"

    var isValid: Bool {
        isValidTagLabel(label)
    }

    var body: some View {
        TextField(labelPlaceholder, text: $label)
            .textInputAutocapitalization(.words)
        PalettePicker(selection: $color)
    }
}

struct TagAssignment: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    let document: StoredDocument
    @State private var selected: Set<UUID> = []
    @State private var newTagLabel = ""
    @State private var newTagColor = ArchiveTagPalette.colors[8]
    var body: some View {
        NavigationStack {
            List {
                Section("Create tag") {
                    TagForm(label: $newTagLabel, color: $newTagColor)
                    Button("Create tag") {
                        Task {
                            if let created = await store.createTag(label: newTagLabel, colorHex: newTagColor) {
                                newTagLabel = ""
                                selected.insert(created.id)
                            }
                        }
                    }
                    .disabled(!isValidTagLabel(newTagLabel))
                }
                Section("Assign tags") {
                    if store.tags.isEmpty {
                        Text("No tags yet. Create one above.")
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.secondary)
                    }
                    ForEach(store.tags) { tag in
                        Button {
                            if selected.contains(tag.id) {
                                selected.remove(tag.id)
                            } else {
                                selected.insert(tag.id)
                            }
                        } label: {
                            HStack {
                                Circle().fill(tagColor(for: tag.colorHex)).frame(width: 12, height: 12)
                                Text(tag.label).foregroundStyle(WatakeColor.text.primary)
                                Spacer()
                                if selected.contains(tag.id) {
                                    Image(systemName: "checkmark").foregroundStyle(WatakeColor.brand.primary)
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tag.label)
                        .accessibilityAddTraits(selected.contains(tag.id) ? [.isSelected] : [])
                        .accessibilityHint("Toggles this tag on the document")
                    }
                }
            }
            .onAppear { selected = Set(document.tagIds) }
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await store.assign(tagIds: Array(selected), document: document) {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .alert("Could not complete change", isPresented: errorBinding) { Button("OK") {} } message: {
                Text(store.errorMessage ?? "Try again.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: {
            if !$0 {
                store.errorMessage = nil
            }
        })
    }
}

struct TagManager: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    @State private var isCreatingTag = false
    @State private var editingTag: Tag?

    var body: some View {
        NavigationStack {
            Group {
                if store.tags.isEmpty {
                    WatakeEmptyState(
                        systemImage: "tag", title: "No tags yet.",
                        message: "Create a tag to start organizing documents."
                    )
                } else {
                    List(store.tags) { tag in
                        Button { editingTag = tag } label: {
                            HStack(spacing: WatakeSpacing.sm) {
                                Circle().fill(tagColor(for: tag.colorHex)).frame(width: 14, height: 14)
                                Text(tag.label).foregroundStyle(WatakeColor.text.primary)
                                Spacer()
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tag.label)
                        .accessibilityHint("Opens editor for this tag")
                    }
                }
            }
            .navigationTitle("Manage Tags")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isCreatingTag = true } label: { Label("New tag", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $isCreatingTag) { TagCreateSheet(store: store) }
            .sheet(item: $editingTag) { tag in TagEditSheet(store: store, tag: tag) }
            .alert("Could not complete change", isPresented: errorBinding) { Button("OK") {} } message: {
                Text(store.errorMessage ?? "Try again.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: {
            if !$0 {
                store.errorMessage = nil
            }
        })
    }
}

struct TagCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    @State private var label = ""
    @State private var color = ArchiveTagPalette.colors[8]

    var body: some View {
        NavigationStack {
            Form { TagForm(label: $label, color: $color) }
                .navigationTitle("New tag")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            Task {
                                if await store.createTag(label: label, colorHex: color) != nil {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!isValid)
                    }
                }
                .alert("Could not create tag", isPresented: errorBinding) { Button("OK") {} } message: {
                    Text(store.errorMessage ?? "Try again.")
                }
        }
    }

    private var isValid: Bool {
        isValidTagLabel(label)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: {
            if !$0 {
                store.errorMessage = nil
            }
        })
    }
}

struct TagEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    let tag: Tag
    @State private var label = ""
    @State private var color = ArchiveTagPalette.colors[8]

    var body: some View {
        NavigationStack {
            Form { TagForm(label: $label, color: $color) }
                .onAppear {
                    label = tag.label
                    color = tag.colorHex
                }
                .navigationTitle("Edit tag")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                if await store.editTag(tag, label: label, colorHex: color) != nil {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!isValid)
                    }
                }
                .alert("Could not save tag", isPresented: errorBinding) { Button("OK") {} } message: {
                    Text(store.errorMessage ?? "Try again.")
                }
        }
    }

    private var isValid: Bool {
        isValidTagLabel(label)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: {
            if !$0 {
                store.errorMessage = nil
            }
        })
    }
}

struct PalettePicker: View {
    @Binding var selection: String
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 4), spacing: WatakeSpacing.sm) {
            ForEach(Array(ArchiveTagPalette.colors.enumerated()), id: \.element) { index, hex in
                Button { selection = hex } label: {
                    Circle().fill(tagColor(at: index)).frame(width: 32, height: 32)
                        .overlay {
                            if selection == hex {
                                Image(systemName: "checkmark").foregroundStyle(WatakeColor.text.onPrimary)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tag color \(index + 1)")
                .accessibilityAddTraits(selection == hex ? [.isSelected] : [])
                .accessibilityHint(selection == hex ? "Selected" : "Selects this tag color")
            }
        }
    }
}

/// Canonicalization mirrors `ArchiveService`'s trim + 1...50 rule so local
/// validation and server-side enforcement never disagree.
func isValidTagLabel(_ label: String) -> Bool {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed.count <= 50
}

/// Legacy or corrupted tag colors (outside the fixed palette) must still
/// render rather than crash. Slate is the documented semantic fallback.
func tagColor(for hex: String) -> Color {
    guard let index = ArchiveTagPalette.colors.firstIndex(of: hex) else {
        return WatakeColor.tag.slate
    }
    return tagColor(at: index)
}

func tagColor(at index: Int) -> Color {
    [
        WatakeColor.tag.red, WatakeColor.tag.orange, WatakeColor.tag.amber, WatakeColor.tag.yellow,
        WatakeColor.tag.lime, WatakeColor.tag.green, WatakeColor.tag.teal, WatakeColor.tag.cyan,
        WatakeColor.tag.blue, WatakeColor.tag.violet, WatakeColor.tag.pink, WatakeColor.tag.slate
    ][index]
}
