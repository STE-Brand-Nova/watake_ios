import ArchiveServices
import DesignSystem
import SwiftUI
import WatakeDomain

struct FolderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    @State private var name = ""
    @State private var color = ArchiveTagPalette.colors[8]
    @State private var iconId = FolderIconCatalog.defaultIdentifier
    @State private var isSubmitting = false

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 120 && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Folder name", text: $name).textInputAutocapitalization(.words)
                }
                Section("Preview") {
                    FolderAppearancePreview(name: name, iconId: iconId, color: tagColor(for: color))
                }
                Section("Icon") {
                    FolderIconPicker(selection: $iconId, color: tagColor(for: color))
                }
                Section("Color") {
                    PalettePicker(selection: $color, accessibilityName: "Folder color")
                }
            }
            .navigationTitle("New folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Creating…" : "Create") {
                        isSubmitting = true
                        Task {
                            defer { isSubmitting = false }
                            if await store.createFolder(name: name, colorHex: color, iconId: iconId) != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

struct DocumentRename: View {
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

struct DocumentMove: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    let document: StoredDocument
    @State private var destinationID: UUID?
    @State private var isMoving = false

    private var candidateFolders: [Folder] {
        store.activeFolders.filter { $0.id != document.folderId }
    }

    var body: some View {
        NavigationStack {
            Form {
                if candidateFolders.isEmpty {
                    Text("No other folders available to move this document into.")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.secondary)
                } else {
                    Picker("Destination folder", selection: $destinationID) {
                        Text("Select folder").tag(UUID?.none)
                        ForEach(candidateFolders) { folder in
                            Text(folder.name).tag(Optional(folder.id))
                        }
                    }
                    .accessibilityLabel("Destination folder selection")
                }
            }
            .navigationTitle("Move document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isMoving ? "Moving…" : "Move") {
                        guard let destinationID, let destination = store.folder(for: destinationID) else { return }
                        isMoving = true
                        Task {
                            if await store.moveDocument(document, to: destination) {
                                dismiss()
                            }
                            isMoving = false
                        }
                    }
                    .disabled(destinationID == nil || isMoving)
                }
            }
        }
    }
}

struct FolderEdit: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: LibraryStore
    let folder: Folder
    @State private var name: String
    @State private var color: String
    @State private var iconId: String
    @State private var isSubmitting = false

    init(store: LibraryStore, folder: Folder) {
        self.store = store
        self.folder = folder
        _name = State(initialValue: folder.name)
        _color = State(initialValue: folder.colorHex)
        _iconId = State(initialValue: folder.iconId)
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 120 && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Folder name", text: $name).textInputAutocapitalization(.words)
                }
                Section("Preview") {
                    FolderAppearancePreview(name: name, iconId: iconId, color: tagColor(for: color))
                }
                Section("Icon") {
                    FolderIconPicker(selection: $iconId, color: tagColor(for: color))
                }
                Section("Color") {
                    PalettePicker(selection: $color, accessibilityName: "Folder color")
                }
            }
            .navigationTitle("Edit folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Saving…" : "Save") {
                        isSubmitting = true
                        Task {
                            defer { isSubmitting = false }
                            if await store.updateFolder(folder, name: name, colorHex: color, iconId: iconId) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
