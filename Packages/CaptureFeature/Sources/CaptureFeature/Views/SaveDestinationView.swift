import DesignSystem
import SwiftUI
import WatakeDomain

public struct SaveDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var state: CaptureReviewState
    public let folderProvider: any CaptureFolderProviding
    public let saver: any CaptureSaving
    public let onSaved: () -> Void

    @State private var activeFolders: [Folder] = []
    @State private var isLoadingFolders = true

    public init(
        state: CaptureReviewState,
        folderProvider: any CaptureFolderProviding,
        saver: any CaptureSaving,
        onSaved: @escaping () -> Void
    ) {
        self.state = state
        self.folderProvider = folderProvider
        self.saver = saver
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Document Name") {
                    TextField("Document name", text: $state.documentName)
                        .accessibilityLabel("Document name")
                }

                Section("Save Location") {
                    if isLoadingFolders {
                        HStack {
                            ProgressView()
                            Text("Loading folders...")
                                .watakeType(.body)
                                .foregroundStyle(WatakeColor.text.secondary)
                        }
                    } else if activeFolders.isEmpty {
                        Text("No folders found. Create one below to save your capture.")
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.secondary)
                    } else {
                        Picker("Target Folder", selection: $state.saveDestinationFolderID) {
                            Text("Select folder").tag(UUID?.none)
                            ForEach(activeFolders) { folder in
                                Text(folder.name).tag(Optional(folder.id))
                            }
                        }
                        .accessibilityLabel("Target folder selection")
                    }
                }

                if activeFolders.isEmpty || state.saveDestinationFolderID == nil {
                    Section("New Folder") {
                        TextField("New folder name", text: $state.newFolderName)
                            .accessibilityLabel("New folder name")
                        WatakeButton("Create Folder", variant: .secondary) {
                            createFolder()
                        }
                        .disabled(state.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Create folder button")
                    }
                }

                if state.pages.count > 1 {
                    Section("Page Grouping") {
                        Picker("Grouping", selection: $state.grouping) {
                            Text("One multi-page document").tag(GalleryGrouping.oneDocument)
                            Text("Separate documents").tag(GalleryGrouping.separateDocuments)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Page grouping mode")
                    }
                }
            }
            .background(WatakeColor.surface.base)
            .navigationTitle("Save to folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        state.isShowingSaveDestination = false
                        dismiss()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Cancel save")
                }

                ToolbarItem(placement: .confirmationAction) {
                    WatakeButton(
                        state.isSaving ? "Saving..." : "Save",
                        variant: .primary
                    ) {
                        save()
                    }
                    .disabled(state.saveDestinationFolderID == nil || state.isSaving || state.isProcessing)
                    .accessibilityLabel("Save capture to folder")
                }
            }
            .task {
                await loadFolders()
            }
            .alert("Could not save capture", isPresented: Binding(
                get: { state.saveError != nil },
                set: {
                    if !$0 {
                        state.saveError = nil
                    }
                }
            )) {
                Button("OK") {}
                Button("Retry") { save() }
            } message: {
                Text(state.saveError ?? "Your review pages remain intact. Try saving again.")
            }
        }
    }

    private func loadFolders() async {
        isLoadingFolders = true
        let folders = await folderProvider.activeFolders()
        activeFolders = folders
        isLoadingFolders = false
        if state.saveDestinationFolderID == nil {
            state.saveDestinationFolderID = folders.first?.id
        }
    }

    private func createFolder() {
        let name = state.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            if let created = try? await folderProvider.createFolder(name: name) {
                await loadFolders()
                state.saveDestinationFolderID = created.id
                state.newFolderName = ""
            }
        }
    }

    private func save() {
        Task {
            await state.save(via: saver) {
                state.isShowingSaveDestination = false
                onSaved()
                dismiss()
            }
        }
    }
}
