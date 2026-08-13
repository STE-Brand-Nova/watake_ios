import DesignSystem
import SwiftUI
import WatakeDomain

public struct SaveDestinationView: View {
    static func preferredFolderID(
        activeFolders: [Folder],
        currentFolderID: UUID?,
        recentFolderID: UUID?
    ) -> UUID? {
        if let currentFolderID, activeFolders.contains(where: { $0.id == currentFolderID }) {
            return currentFolderID
        }
        return activeFolders.first(where: { $0.id == recentFolderID })?.id ?? activeFolders.first?.id
    }

    static func selectionAfterCreating(folder: Folder, activeFolders: [Folder]) -> UUID? {
        activeFolders.contains(where: { $0.id == folder.id }) ? folder.id : nil
    }

    @Environment(\.dismiss) private var dismiss
    @Bindable public var state: CaptureReviewState
    public let folderProvider: any CaptureFolderProviding
    public let saver: any CaptureSaving
    public let onSaved: (UUID) -> Void

    @State private var activeFolders: [Folder] = []
    @State private var isLoadingFolders = true
    @State private var folderError: String?
    @State private var isCreatingFolder = false
    @State private var folderCreationTask: Task<Void, Never>?
    @FocusState private var isNewFolderFieldFocused: Bool

    public init(
        state: CaptureReviewState,
        folderProvider: any CaptureFolderProviding,
        saver: any CaptureSaving,
        onSaved: @escaping (UUID) -> Void
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
                        VStack(alignment: .leading, spacing: WatakeSpacing.md) {
                            Text("Create a folder first")
                                .watakeType(.title2)
                                .foregroundStyle(WatakeColor.text.primary)
                            Text("Watake saves imported images inside a folder so you can find them later.")
                                .watakeType(.body)
                                .foregroundStyle(WatakeColor.text.secondary)
                            TextField("Folder name", text: $state.newFolderName)
                                .focused($isNewFolderFieldFocused)
                                .accessibilityLabel("New folder name")
                            if let folderError {
                                Text(folderError)
                                    .watakeType(.caption)
                                    .foregroundStyle(WatakeColor.status.danger)
                                    .accessibilityLabel("Folder name error: \(folderError)")
                            }
                            WatakeButton("Create folder", variant: .primary) {
                                createFolder()
                            }
                            .disabled(state.newFolderName.isEmpty || state.isSaving || isCreatingFolder)
                            .accessibilityLabel("Create folder")
                        }
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
                    .disabled(state.isSaving || isCreatingFolder)
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
                _ = await loadFolders()
                if activeFolders.isEmpty {
                    isNewFolderFieldFocused = true
                }
            }
            .onDisappear {
                folderCreationTask?.cancel()
                folderCreationTask = nil
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

    private func loadFolders() async -> Bool {
        isLoadingFolders = true
        let folders = await folderProvider.activeFolders()
        guard !Task.isCancelled else { return false }
        activeFolders = folders
        isLoadingFolders = false
        if folders.isEmpty {
            state.saveDestinationFolderID = nil
        } else {
            let recentID = await folderProvider.mostRecentlyUsedFolderID()
            guard !Task.isCancelled else { return false }
            state.saveDestinationFolderID = Self.preferredFolderID(
                activeFolders: folders,
                currentFolderID: state.saveDestinationFolderID,
                recentFolderID: recentID
            )
        }
        return true
    }

    private func createFolder() {
        guard !isCreatingFolder else { return }
        let name = trimmedFolderName
        isCreatingFolder = true
        let task = Task {
            do {
                try Task.checkCancellation()
                let created = try await folderProvider.createFolder(name: name)
                try Task.checkCancellation()
                guard await loadFolders() else { return }
                try Task.checkCancellation()
                state.saveDestinationFolderID = Self.selectionAfterCreating(
                    folder: created,
                    activeFolders: activeFolders
                )
                state.newFolderName = ""
                folderError = nil
                isNewFolderFieldFocused = false
            } catch let error as DomainValidationError {
                guard !Task.isCancelled else { return }
                if case .emptyName = error {
                    folderError = "Folder name cannot be empty."
                } else {
                    folderError = "Folder could not be created. Try again."
                }
            } catch {
                guard !Task.isCancelled else { return }
                folderError = "Folder could not be created. Try again."
            }
            if !Task.isCancelled {
                isCreatingFolder = false
                folderCreationTask = nil
            }
        }
        folderCreationTask = task
    }

    private var trimmedFolderName: String {
        state.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        Task {
            await state.save(via: saver) {
                guard let folderID = state.saveDestinationFolderID else { return }
                state.isShowingSaveDestination = false
                onSaved(folderID)
                dismiss()
            }
        }
    }
}
