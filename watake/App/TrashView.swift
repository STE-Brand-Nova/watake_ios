import ArchiveServices
import DesignSystem
import SwiftUI
import WatakeDomain

struct TrashView: View {
    @Bindable var store: LibraryStore
    @State private var recoveryMessage: String?
    @State private var retentionNow = Date.now

    var body: some View {
        List {
            if !store.trashedFolders.isEmpty {
                Section("Folders") {
                    ForEach(store.trashedFolders) { folder in
                        trashRow(name: folder.name, subtitle: "Folder", deletedAt: folder.deletedAt) {
                            restore { await store.restoreFolder(folder) }
                        }
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
                        trashRow(name: document.name, subtitle: "Original location: \(location)", deletedAt: document.deletedAt) {
                            restore { await store.restoreDocument(document) }
                        }
                    }
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
        .background(WatakeColor.surface.base)
        .navigationTitle("Trash")
        .task { await store.load() }
        .task { await refreshRetentionAtDayBoundary() }
        .alert("Could not restore item", isPresented: recoveryBinding) { Button("OK") {} } message: {
            Text(recoveryMessage ?? "Try again.")
        }
    }

    private func trashRow(name: String, subtitle: String, deletedAt: Date?, restore: @escaping () -> Void) -> some View {
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
    }

    private func restore(_ operation: @escaping () async -> Bool) {
        Task {
            guard await operation() == false else { return }
            recoveryMessage = store.errorMessage ?? "Could not restore item. Try again."
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
