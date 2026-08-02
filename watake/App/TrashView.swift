import ArchiveServices
import DesignSystem
import SwiftUI
import WatakeDomain

struct TrashView: View {
    @Bindable var store: LibraryStore
    var body: some View {
        List {
            ForEach(store.trashedFolders) { folder in
                trashRow(name: folder.name, location: "Folder", deletedAt: folder.deletedAt) { Task { await store.restoreFolder(folder) } }
            }
            ForEach(store.trashedDocuments) { document in
                let location = store.folder(for: document.folderId)?.name ?? "Original folder unavailable"
                trashRow(name: document.name, location: location, deletedAt: document.deletedAt) {
                    Task { await store.restoreDocument(document) }
                }
            }
        }
        .overlay {
            if store.trashedFolders.isEmpty && store.trashedDocuments.isEmpty {
                WatakeEmptyState(
                    systemImage: "trash",
                    title: "Trash is empty.",
                    message: "Deleted items appear here for 30 days."
                )
            }
        }
        .background(WatakeColor.surface.base).navigationTitle("Trash").task { await store.load() }
    }

    private func trashRow(name: String, location: String, deletedAt: Date?, restore: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name).foregroundStyle(WatakeColor.text.primary)
                Text("Original location: \(location)").watakeType(.caption).foregroundStyle(WatakeColor.text.secondary)
                if let deletedAt {
                    Text("\(ArchiveService.retentionDaysRemaining(deletedAt: deletedAt, now: .now)) days remaining").watakeType(.caption)
                        .foregroundStyle(WatakeColor.status.warning)
                }
            }
            Spacer()
            Button("Restore", action: restore).frame(minHeight: 44)
        }
    }
}
