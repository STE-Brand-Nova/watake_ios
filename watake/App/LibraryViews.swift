import ArchiveServices
import DesignSystem
import DocumentViewerFeature
import SwiftUI
import UIKit
import WatakeDomain

struct LibraryView: View {
    @Bindable var store: LibraryStore
    @State private var isCreatingFolder = false
    @State private var editingFolder: Folder?
    @State private var isManagingTags = false

    private var selectedFolder: Folder? {
        guard let selectedFolderID = store.selectedFolderID else { return nil }
        return store.folder(for: selectedFolderID)
    }

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
                    Button("Folders") { store.closeFolder() }.accessibilityLabel("Back to folders")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { isCreatingFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    Button { isManagingTags = true } label: { Label("Manage Tags", systemImage: "tag") }
                } label: {
                    Image(systemName: "plus.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Library actions")
            }
        }
        .task { await store.load() }
        .sheet(isPresented: $isCreatingFolder) { FolderEditor(store: store) }
        .sheet(item: $editingFolder) { folder in FolderEdit(store: store, folder: folder) }
        .sheet(isPresented: $isManagingTags) { TagManager(store: store) }
        .safeAreaInset(edge: .top, spacing: WatakeSpacing.sm) {
            if let undo = store.pendingTrashUndo {
                TrashUndoBanner {
                    Task { await store.undoTrash() }
                }
                .id(undo.id)
            }
        }
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
                        Button {
                            store.openFolder(id: folder.id)
                        } label: {
                            FolderCard(folder: folder, count: store.documents(in: folder).count)
                        }
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

private struct TrashUndoBanner: View {
    let undo: () -> Void

    var body: some View {
        HStack(spacing: WatakeSpacing.md) {
            Text("Moved to Trash")
                .watakeType(.bodyEmphasis)
                .foregroundStyle(WatakeColor.text.primary)
            Spacer(minLength: 0)
            Button("Undo", action: undo)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Undo move to Trash")
                .accessibilityHint("Restores the most recently deleted item")
        }
        .padding(.horizontal, WatakeSpacing.md)
        .background(WatakeColor.surface.raised)
        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: WatakeRadius.md)
                .stroke(WatakeColor.border.subtle, lineWidth: 1)
        }
        .padding(.horizontal, WatakeSpacing.md)
        .accessibilityElement(children: .contain)
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
    @State private var movingDocument: StoredDocument?

    var body: some View {
        GeometryReader { proxy in
            let isCompact = WatakeLayout.widthClass(for: proxy.size.width) == .compact
            Group {
                if !isCompact, let documentID = store.selectedDocumentID {
                    DocumentViewerView(
                        model: store.documentViewerModel(for: documentID),
                        presetStore: store.watermarkPresetStore,
                        onClose: { store.closeDocument() }
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Documents") { store.closeDocument() }.accessibilityLabel("Back to documents")
                        }
                    }
                } else {
                    documentBrowser(width: proxy.size.width)
                }
            }
            .fullScreenCover(isPresented: compactViewerPresented(isCompact: isCompact)) {
                if let documentID = store.selectedDocumentID {
                    NavigationStack {
                        DocumentViewerView(
                            model: store.documentViewerModel(for: documentID),
                            presetStore: store.watermarkPresetStore,
                            onClose: { store.closeDocument() }
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") { store.closeDocument() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func documentBrowser(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            TagFilterRow(store: store)
            Group {
                switch store.layout(for: folder) {
                case .list: documentList
                case .grid: documentGrid(width: width)
                }
            }
        }
        .toolbar {
            if store.layout(for: folder) == .list, store.selectedTagFilterID == nil {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Picker(
                    "Document layout",
                    selection: Binding(get: { store.layout(for: folder) }, set: { store.setLayout($0, for: folder) })
                ) {
                    Image(systemName: "list.bullet").tag(DocumentLayout.list)
                    Image(systemName: "square.grid.2x2").tag(DocumentLayout.grid)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Document layout")
            }
        }
        .sheet(item: $editingDocument) { document in
            if isAssigningTags {
                TagAssignment(store: store, document: document)
            } else {
                DocumentRename(store: store, document: document)
            }
        }
        .sheet(item: $movingDocument) { document in
            DocumentMove(store: store, document: document)
        }
    }

    private var documentList: some View {
        let ordered = store.filteredDocuments(in: folder)
        return List {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, document in
                HStack(spacing: WatakeSpacing.md) {
                    Button { store.openDocument(document) } label: {
                        HStack(spacing: WatakeSpacing.md) {
                            DocumentThumbnail(store: store, document: document)
                            VStack(alignment: .leading) {
                                Text(document.name).foregroundStyle(WatakeColor.text.primary)
                                Text("\(document.pages.count) page\(document.pages.count == 1 ? "" : "s")")
                                    .watakeType(.caption).foregroundStyle(WatakeColor.text.secondary)
                                if !document.tagIds.isEmpty {
                                    DocumentTagChips(store: store, tagIds: document.tagIds)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityLabel(documentAccessibilityLabel(document))
                    .accessibilityHint("Opens the document")

                    documentActionsMenu(for: document, index: index, ordered: ordered)
                }
            }
            .onMove { indexes, destination in
                guard store.selectedTagFilterID == nil else { return }
                var reordered = ordered
                reordered.move(fromOffsets: indexes, toOffset: destination)
                Task { await store.reorder(folder: folder, documents: reordered) }
            }
        }
        .overlay {
            if ordered.isEmpty {
                WatakeEmptyState(systemImage: "doc.badge.plus", title: "Nothing here yet.", message: "Capture a document to get started.")
            }
        }
    }

    private func documentGrid(width: CGFloat) -> some View {
        let ordered = store.filteredDocuments(in: folder)
        return ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: WatakeSpacing.md),
                    count: WatakeLayout.columnCount(for: width)
                ),
                spacing: WatakeSpacing.md
            ) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, document in
                    documentGridCell(document: document, index: index, ordered: ordered)
                }
            }
            .padding(WatakeLayout.gutter(for: width))
        }
        .overlay {
            if ordered.isEmpty {
                WatakeEmptyState(systemImage: "doc.badge.plus", title: "Nothing here yet.", message: "Capture a document to get started.")
            }
        }
    }

    private func documentGridCell(document: StoredDocument, index: Int, ordered: [StoredDocument]) -> some View {
        WatakeCard {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                HStack {
                    Spacer(minLength: 0)
                    documentActionsMenu(for: document, index: index, ordered: ordered)
                }
                Button { store.openDocument(document) } label: {
                    VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                        DocumentGridThumbnail(store: store, document: document)
                        Text(document.name).watakeType(.bodyEmphasis).foregroundStyle(WatakeColor.text.primary).lineLimit(2)
                        Text("\(document.pages.count) page\(document.pages.count == 1 ? "" : "s")")
                            .watakeType(.caption).foregroundStyle(WatakeColor.text.secondary)
                        if !document.tagIds.isEmpty {
                            DocumentTagChips(store: store, tagIds: document.tagIds)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel(documentAccessibilityLabel(document))
                .accessibilityHint("Opens the document")
            }
        }
    }

    private func documentActionsMenu(for document: StoredDocument, index: Int, ordered: [StoredDocument]) -> some View {
        Menu {
            Button("Open") { store.openDocument(document) }
            Button("Rename") {
                isAssigningTags = false
                editingDocument = document
            }
            Button("Tags") {
                isAssigningTags = true
                editingDocument = document
            }
            Button("Move…") { movingDocument = document }
            Divider()
            Button("Move Up") { Task { await moveOrder(document: document, index: index, ordered: ordered, offset: -1) } }
                .disabled(index == 0 || store.selectedTagFilterID != nil)
            Button("Move Down") { Task { await moveOrder(document: document, index: index, ordered: ordered, offset: 1) } }
                .disabled(index == ordered.count - 1 || store.selectedTagFilterID != nil)
            Divider()
            Button("Move to Trash", role: .destructive) { Task { await store.trashDocument(document) } }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("More actions for \(document.name)")
    }

    private func moveOrder(document: StoredDocument, index: Int, ordered: [StoredDocument], offset: Int) async {
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        var reordered = ordered
        reordered.swapAt(index, target)
        await store.reorder(folder: folder, documents: reordered)
    }

    private func compactViewerPresented(isCompact: Bool) -> Binding<Bool> {
        Binding(
            get: { isCompact && store.selectedDocumentID != nil },
            set: {
                if !$0 {
                    store.closeDocument()
                }
            }
        )
    }
}

private struct DocumentThumbnail: View {
    @Bindable var store: LibraryStore
    let document: StoredDocument
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
            if document.hasOCRText {
                OCRBadge()
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

private struct DocumentGridThumbnail: View {
    @Bindable var store: LibraryStore
    let document: StoredDocument
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
            if document.hasOCRText {
                OCRBadge()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
        .accessibilityHidden(true)
        .task(id: document.id) {
            guard let data = await store.thumbnailData(for: document) else { return }
            image = UIImage(data: data)
        }
    }
}

private struct OCRBadge: View {
    var body: some View {
        Text("T")
            .watakeType(.caption)
            .foregroundStyle(WatakeColor.text.onPrimary)
            .padding(WatakeSpacing.xxs)
            .background(WatakeColor.brand.primary)
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}

private func documentAccessibilityLabel(_ document: StoredDocument) -> String {
    let OCRSuffix = document.hasOCRText ? ", extracted text available" : ""
    return "\(document.name), \(document.pages.count) pages\(OCRSuffix)"
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

private struct DocumentMove: View {
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
