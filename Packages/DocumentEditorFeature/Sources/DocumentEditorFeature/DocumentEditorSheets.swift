#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain

    struct SaveCopySheet: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: DocumentEditorModel
        @State private var name = ""
        @State private var folderID: UUID?

        var body: some View {
            NavigationStack {
                Form {
                    TextField("Document name", text: $name)
                    Picker("Folder", selection: $folderID) {
                        ForEach(model.folders) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                .navigationTitle("Save a Copy")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard let folderID else { return }
                            Task {
                                if await model.saveCopy(name: name, folderID: folderID) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || folderID == nil)
                    }
                }
                .onAppear {
                    name = "\(model.document.name) – Copy"
                    folderID = model.document.folderId
                }
            }
            .presentationDetents([.medium])
        }
    }

    struct PageTargetsSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: DocumentEditorModel
        @State private var selected: Set<UUID> = []

        var body: some View {
            NavigationStack {
                List(model.pages) { page in
                    Button {
                        if selected.contains(page.id) {
                            selected.remove(page.id)
                        } else {
                            selected.insert(page.id)
                        }
                    } label: {
                        HStack {
                            Text("Page \(page.index + 1)")
                            Spacer()
                            if selected.contains(page.id) {
                                Image(systemName: "checkmark").foregroundStyle(WatakeColor.brand.primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Duplicate to Pages")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Duplicate") {
                            model.duplicateSelected(to: selected)
                            dismiss()
                        }
                        .disabled(selected.isEmpty)
                    }
                }
            }
        }
    }

#endif
