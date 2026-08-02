import ArchiveServices
import DesignSystem
import SwiftUI
import UIKit
import WatakeDomain

struct LibraryView: View {
    @Bindable var store: LibraryStore
    @State private var isCreatingFolder = false
    @State private var selectedFolder: Folder?
    @State private var editingFolder: Folder?

    var body: some View {
        Group {
            if store.isLoading && store.folders.isEmpty {
                ProgressView("Loading archive")
            } else if let selectedFolder {
                FolderDocumentsView(store: store, folder: selectedFolder)
            } else if store.activeFolders.isEmpty {
                WatakeEmptyState(
                    systemImage: "folder.badge.plus", title: "Your archive is empty.",
                    message: "Create your first folder to start organizing scans."
                )
            } else {
                folderGrid
            }
        }
        .background(WatakeColor.surface.base)
        .navigationTitle(selectedFolder?.name ?? "Folders")
        .toolbar {
            if selectedFolder != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Folders") { selectedFolder = nil }.accessibilityLabel("Back to folders")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCreatingFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
            }
        }
        .task { await store.load() }
        .sheet(isPresented: $isCreatingFolder) { FolderEditor(store: store) }
        .sheet(item: $editingFolder) { folder in FolderEdit(store: store, folder: folder) }
        .alert("Could not complete change", isPresented: errorBinding) { Button("OK") {} } message: {
            Text(store.errorMessage ?? "Try again.")
        }
    }

    private var folderGrid: some View {
        GeometryReader { proxy in
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: WatakeSpacing.md),
                count: WatakeLayout.columnCount(for: proxy.size.width)
            )
            ScrollView {
                LazyVGrid(columns: columns, spacing: WatakeSpacing.md) {
                    ForEach(store.activeFolders) { folder in
                        Button { selectedFolder = folder } label: { FolderCard(folder: folder, count: store.documents(in: folder).count) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename or change color") { editingFolder = folder }
                                Button("Move to Trash", role: .destructive) { Task { await store.trashFolder(folder) } }
                            }
                    }
                }
                .padding(WatakeLayout.gutter(for: proxy.size.width))
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

private struct FolderCard: View {
    let folder: Folder
    let count: Int
    var body: some View {
        WatakeCard {
            HStack(alignment: .top, spacing: WatakeSpacing.sm) {
                Image(systemName: "folder.fill").foregroundStyle(tagColor(for: folder.colorHex)).font(.title2)
                VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
                    Text(folder.name).watakeType(.bodyEmphasis).foregroundStyle(WatakeColor.text.primary).lineLimit(2)
                    Text("\(count) document\(count == 1 ? "" : "s")").watakeType(.caption).foregroundStyle(WatakeColor.text.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityLabel("\(folder.name), \(count) documents")
    }
}

private struct FolderDocumentsView: View {
    @Bindable var store: LibraryStore
    let folder: Folder
    @State private var editingDocument: StoredDocument?
    @State private var isAssigningTags = false

    var body: some View {
        List {
            ForEach(store.documents(in: folder)) { document in
                HStack(spacing: WatakeSpacing.md) {
                    DocumentThumbnail(store: store, document: document)
                    VStack(alignment: .leading) {
                        Text(document.name).foregroundStyle(WatakeColor.text.primary)
                        Text("\(document.pages.count) page\(document.pages.count == 1 ? "" : "s")")
                            .watakeType(.caption).foregroundStyle(WatakeColor.text.secondary)
                    }
                    Spacer()
                    if !document.tagIds.isEmpty {
                        Image(systemName: "tag.fill").foregroundStyle(WatakeColor.status.warning)
                    }
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Rename") {
                        isAssigningTags = false
                        editingDocument = document
                    }
                    Button("Tags") {
                        isAssigningTags = true
                        editingDocument = document
                    }
                    Button("Move to Trash", role: .destructive) { Task { await store.trashDocument(document) } }
                }
                .accessibilityLabel("\(document.name), \(document.pages.count) pages")
            }
            .onMove { indexes, destination in
                var reordered = store.documents(in: folder)
                reordered.move(fromOffsets: indexes, toOffset: destination)
                Task { await store.reorder(folder: folder, documents: reordered) }
            }
        }
        .overlay {
            if store.documents(in: folder).isEmpty {
                WatakeEmptyState(systemImage: "doc.badge.plus", title: "Nothing here yet.", message: "Capture a document to get started.")
            }
        }
        .toolbar { EditButton() }
        .sheet(item: $editingDocument) { document in
            if isAssigningTags {
                TagAssignment(store: store, document: document)
            } else {
                DocumentRename(store: store, document: document)
            }
        }
    }
}

private struct DocumentThumbnail: View {
    @Bindable var store: LibraryStore
    let document: StoredDocument
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "doc.text.image")
                    .foregroundStyle(WatakeColor.text.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
        .accessibilityHidden(true)
        .task(id: document.id) {
            guard let data = await store.thumbnailData(for: document) else { return }
            image = UIImage(data: data)
        }
    }
}

private struct FolderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    @State private var name = ""
    @State private var color = ArchiveTagPalette.colors[8]
    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder name", text: $name).textInputAutocapitalization(.words)
                PalettePicker(selection: $color)
            }
            .navigationTitle("New folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await store.createFolder(name: name, colorHex: color) != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct DocumentRename: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    let document: StoredDocument
    @State private var name = ""
    var body: some View {
        NavigationStack {
            Form { TextField("Document name", text: $name) }
                .onAppear { name = document.name }
                .navigationTitle("Rename document")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                await store.renameDocument(document, name: name)
                                dismiss()
                            }
                        }
                    }
                }
        }
    }
}

private struct FolderEdit: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    let folder: Folder
    @State private var name = ""
    @State private var color = ArchiveTagPalette.colors[8]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder name", text: $name)
                PalettePicker(selection: $color)
            }
            .onAppear { name = folder.name
                color = folder.colorHex
            }
            .navigationTitle("Edit folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await store.renameFolder(folder, name: name)
                            await store.recolorFolder(folder, colorHex: color)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

private struct TagAssignment: View {
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
                    TextField("Tag label", text: $newTagLabel)
                    PalettePicker(selection: $newTagColor)
                    Button("Create tag") {
                        Task {
                            await store.createTag(label: newTagLabel, colorHex: newTagColor)
                            newTagLabel = ""
                        }
                    }
                    .disabled(newTagLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Assign tags") {
                    ForEach(store.tags) { tag in
                        Button {
                            if selected.contains(tag.id) {
                                selected.remove(tag.id)
                            } else {
                                selected.insert(tag.id)
                            }
                        } label: {
                            Label(tag.label, systemImage: selected.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
            }
            .onAppear { selected = Set(document.tagIds) }
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await store.assign(tagIds: Array(selected), document: document)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

private struct PalettePicker: View {
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
                }.accessibilityLabel("Tag color \(index + 1)")
            }
        }
    }
}

private func tagColor(for hex: String) -> Color {
    tagColor(at: ArchiveTagPalette.colors.firstIndex(of: hex) ?? 8)
}

private func tagColor(at index: Int) -> Color {
    [
        WatakeColor.tag.red, WatakeColor.tag.orange, WatakeColor.tag.amber, WatakeColor.tag.yellow,
        WatakeColor.tag.lime, WatakeColor.tag.green, WatakeColor.tag.teal, WatakeColor.tag.cyan,
        WatakeColor.tag.blue, WatakeColor.tag.violet, WatakeColor.tag.pink, WatakeColor.tag.slate
    ][index]
}
