import ArchiveServices
import DesignSystem
import SwiftUI
import WatakeDomain

struct TrashView: View {
    @Bindable var store: LibraryStore
    @State private var recoveryMessage: String?
    @State private var retentionNow = Date.now
    @State private var documentToDelete: StoredDocument?
    @State private var folderToDelete: Folder?
    @State private var renditionToDelete: WatermarkRendition?

    var body: some View {
        List {
            if !store.trashedFolders.isEmpty {
                Section("Folders") {
                    ForEach(store.trashedFolders) { folder in
                        trashRow(name: folder.name, subtitle: "Folder", deletedAt: folder.deletedAt, restore: {
                            restore { await store.restoreFolder(folder) }
                        }, deleteAction: {
                            folderToDelete = folder
                        })
                    }
                }
            }
            if !store.trashedDocuments.isEmpty {
                Section("Documents") {
                    ForEach(store.trashedDocuments) { document in
                        let folder = store.folder(for: document.folderId)
                        let location = folder?.deletedAt == nil
                            ? folder?.name ?? "Original folder unavailable"
                            : "Original folder unavailable"
                        trashRow(name: document.name, subtitle: "Original location: \(location)", deletedAt: document.deletedAt, restore: {
                            restore { await store.restoreDocument(document) }
                        }, deleteAction: {
                            documentToDelete = document
                        })
                    }
                }
            }
            if !store.trashedWatermarkRenditions.isEmpty {
                Section("Watermarked Copies") {
                    ForEach(store.trashedWatermarkRenditions) { rendition in
                        let recipient = store.issuance(containing: rendition.id)?.recipientNameSnapshot ?? "Unassigned"
                        trashRow(
                            name: rendition.originalNameSnapshot,
                            subtitle: "Recipient: \(recipient) · Version \(rendition.version)",
                            deletedAt: rendition.deletedAt,
                            restore: { restore { await store.restoreWatermarkRendition(rendition) } },
                            deleteAction: { renditionToDelete = rendition }
                        )
                    }
                }
            }
        }
        .overlay {
            if store.trashedFolders.isEmpty && store.trashedDocuments.isEmpty && store.trashedWatermarkRenditions.isEmpty {
                WatakeEmptyState(
                    systemImage: "trash",
                    title: "Trash is empty.",
                    message: "Deleted items appear here for 30 days."
                )
            }
        }
        .background(WatakeColor.surface.base)
        .navigationTitle("Trash")
        .task { await store.load() }
        .task { await refreshRetentionAtDayBoundary() }
        .alert("Could not restore item", isPresented: recoveryBinding) { Button("OK") {} } message: {
            Text(recoveryMessage ?? "Try again.")
        }
        .confirmationDialog(
            "Delete Document Permanently?",
            isPresented: Binding(
                get: { documentToDelete != nil },
                set: {
                    if !$0 {
                        documentToDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let document = documentToDelete {
                    deletePermanently(document)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(documentDeletionMessage)
        }
        .confirmationDialog(
            "Delete Folder Permanently?",
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: {
                    if !$0 {
                        folderToDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let folder = folderToDelete {
                    deletePermanently(folder)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(folderDeletionMessage)
        }
        .confirmationDialog(
            "Delete Watermarked Copy Permanently?",
            isPresented: Binding(
                get: { renditionToDelete != nil },
                set: {
                    if !$0 {
                        renditionToDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let rendition = renditionToDelete {
                    deletePermanently(rendition)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the derived pages. The original document is unchanged.")
        }
    }

    private func trashRow(
        name: String,
        subtitle: String,
        deletedAt: Date?,
        restore: @escaping () -> Void,
        deleteAction: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name).foregroundStyle(WatakeColor.text.primary)
                Text(subtitle).watakeType(.caption).foregroundStyle(WatakeColor.text.secondary)
                if let deletedAt {
                    Text(TrashRetentionText.message(daysRemaining: ArchiveService.retentionDaysRemaining(
                        deletedAt: deletedAt,
                        now: retentionNow
                    )))
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.status.warning)
                }
            }
            Spacer()
            Button("Restore", action: restore)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Restore \(name)")
                .accessibilityHint("Returns this item to its original location when available")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete Permanently", role: .destructive, action: deleteAction)
        }
    }

    private func restore(_ operation: @escaping () async -> Bool) {
        Task {
            guard await operation() == false else { return }
            recoveryMessage = store.errorMessage ?? "Could not restore item. Try again."
            store.errorMessage = nil
        }
    }

    private func deletePermanently(_ document: StoredDocument) {
        Task {
            guard await store.deletePermanently(document) == false else { return }
            recoveryMessage = store.errorMessage ?? "Could not delete item. Try again."
            store.errorMessage = nil
        }
    }

    private func deletePermanently(_ folder: Folder) {
        Task {
            guard await store.deletePermanently(folder) == false else { return }
            recoveryMessage = store.errorMessage ?? "Could not delete item. Try again."
            store.errorMessage = nil
        }
    }

    private func deletePermanently(_ rendition: WatermarkRendition) {
        Task {
            guard await store.deletePermanently(rendition) == false else { return }
            recoveryMessage = store.errorMessage ?? "Could not delete copy. Try again."
            store.errorMessage = nil
        }
    }

    private func refreshRetentionAtDayBoundary() async {
        let calendar = Calendar.autoupdatingCurrent
        while !Task.isCancelled {
            let current = Date.now
            let startOfToday = calendar.startOfDay(for: current)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return }
            do {
                try await Task.sleep(for: .seconds(max(1, nextDay.timeIntervalSince(current))))
            } catch is CancellationError {
                return
            } catch {
                return
            }
            retentionNow = .now
        }
    }

    private var recoveryBinding: Binding<Bool> {
        Binding(get: { recoveryMessage != nil }, set: {
            if !$0 {
                recoveryMessage = nil
            }
        })
    }

    private var documentDeletionMessage: String {
        guard let documentToDelete else { return "This removes the document's local files and cannot be undone." }
        let copies = store.relatedCopyCount(for: documentToDelete.id)
        return copies == 0
            ? "This removes the document's local files and cannot be undone."
            : "This also permanently removes \(copies) related watermarked cop\(copies == 1 ? "y" : "ies") and cannot be undone."
    }

    private var folderDeletionMessage: String {
        guard let folderToDelete else { return "This permanently removes the folder and its documents." }
        let copies = store.relatedCopyCount(in: folderToDelete)
        return copies == 0
            ? "This permanently removes the folder and its documents."
            : "This permanently removes the folder, its documents, and \(copies) related watermarked cop\(copies == 1 ? "y" : "ies")."
    }
}

enum TrashRetentionText {
    static func message(daysRemaining: Int) -> String {
        switch daysRemaining {
        case 0: "Expires today"
        case 1: "1 day remaining"
        default: "\(daysRemaining) days remaining"
        }
    }
}
