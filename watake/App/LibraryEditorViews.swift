import ArchiveServices
import DesignSystem
import SwiftUI
import WatakeDomain

struct FolderEditor: View {
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
    @State private var name = ""
    @State private var color = ArchiveTagPalette.colors[8]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder name", text: $name)
                PalettePicker(selection: $color)
            }
            .onAppear {
                name = folder.name
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
