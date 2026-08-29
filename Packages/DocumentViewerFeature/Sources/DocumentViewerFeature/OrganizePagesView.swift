#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UniformTypeIdentifiers
    import WatakeDomain

    struct OrganizePagesView: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: OrganizePagesModel
        let onSaved: () -> Void
        @State private var draggedPageID: UUID?
        @State private var showsDiscardConfirmation = false

        var body: some View {
            NavigationStack {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: WatakeSpacing.lg) {
                            Label(
                                "Touch and hold a page, then drag to reorder.",
                                systemImage: "hand.draw"
                            )
                            .watakeType(.body)
                            .foregroundStyle(WatakeColor.text.secondary)

                            LazyVGrid(columns: columns(for: proxy.size.width), spacing: WatakeSpacing.lg) {
                                ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                                    OrganizePageCard(
                                        page: page,
                                        pageNumber: index + 1,
                                        pageCount: model.pages.count,
                                        isDragging: draggedPageID == page.id,
                                        model: model
                                    )
                                    .onDrag {
                                        draggedPageID = page.id
                                        return NSItemProvider(object: page.id.uuidString as NSString)
                                    } preview: {
                                        OrganizePageDragPreview(page: page, pageNumber: index + 1, model: model)
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: PageReorderDropDelegate(
                                            targetPageID: page.id,
                                            draggedPageID: $draggedPageID,
                                            model: model,
                                            reduceMotion: reduceMotion
                                        )
                                    )
                                    .contextMenu {
                                        Button("Move Earlier") { animate { model.moveEarlier(pageID: page.id) } }
                                            .disabled(index == 0)
                                        Button("Move Later") { animate { model.moveLater(pageID: page.id) } }
                                            .disabled(index == model.pages.count - 1)
                                    }
                                    .accessibilityAction(named: "Move Earlier") {
                                        animate { model.moveEarlier(pageID: page.id) }
                                    }
                                    .accessibilityAction(named: "Move Later") {
                                        animate { model.moveLater(pageID: page.id) }
                                    }
                                }
                            }
                        }
                        .padding(WatakeLayout.gutter(for: proxy.size.width))
                    }
                }
                .background(WatakeColor.surface.base)
                .navigationTitle("Organize Pages")
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(model.hasChanges || model.isSaving)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancel() }
                            .disabled(model.isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(model.isSaving ? "Saving…" : "Done") {
                            Task {
                                if await model.save() {
                                    onSaved()
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(model.isSaving)
                    }
                }
                .confirmationDialog(
                    "Discard page changes?",
                    isPresented: $showsDiscardConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Keep Editing", role: .cancel) {}
                    Button("Discard Changes", role: .destructive) { dismiss() }
                }
                .alert("Pages couldn't be reorganized.", isPresented: errorBinding) {
                    Button("OK") { model.clearError() }
                } message: {
                    Text(errorMessage)
                }
            }
        }

        private var errorBinding: Binding<Bool> {
            Binding(get: { model.error != nil }, set: {
                if !$0 {
                    model.clearError()
                }
            })
        }

        private var errorMessage: String {
            switch model.error {
            case .documentChanged:
                "The document changed while you were editing. Reopen Organize Pages and try again."
            case .unavailable:
                "Your original pages are unchanged. Try again."
            case nil:
                ""
            }
        }

        private func columns(for width: CGFloat) -> [GridItem] {
            let count: Int = if WatakeLayout.widthClass(for: width) == .compact {
                2
            } else {
                min(5, max(3, Int(width / 220)))
            }
            return Array(repeating: GridItem(.flexible(), spacing: WatakeSpacing.md), count: count)
        }

        private func cancel() {
            if model.hasChanges {
                showsDiscardConfirmation = true
            } else {
                dismiss()
            }
        }

        private func animate(_ changes: () -> Void) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25), changes)
        }
    }

    private struct OrganizePageCard: View {
        let page: DocumentPage
        let pageNumber: Int
        let pageCount: Int
        let isDragging: Bool
        let model: OrganizePagesModel

        var body: some View {
            VStack(spacing: WatakeSpacing.sm) {
                OrganizePageImage(page: page, model: model)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous)
                            .strokeBorder(
                                isDragging ? WatakeColor.brand.primary : WatakeColor.border.subtle,
                                lineWidth: isDragging ? 2 : 1
                            )
                    }

                Text("Page \(pageNumber)")
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                    .frame(maxWidth: .infinity)
            }
            .padding(WatakeSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: WatakeRadius.lg, style: .continuous)
                    .fill(WatakeColor.surface.raised)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WatakeRadius.lg, style: .continuous)
                    .strokeBorder(isDragging ? WatakeColor.brand.primary : WatakeColor.border.subtle, lineWidth: 1)
            }
            .scaleEffect(isDragging ? 1.04 : 1)
            .opacity(isDragging ? 0.86 : 1)
            .contentShape(RoundedRectangle(cornerRadius: WatakeRadius.lg, style: .continuous))
            .hoverEffect(.lift)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(pageNumber) of \(pageCount)")
            .accessibilityHint("Touch and hold, then drag to reorder. More actions offers keyboard alternatives.")
        }
    }

    private struct OrganizePageImage: View {
        let page: DocumentPage
        let model: OrganizePagesModel
        @State private var data: Data?
        @State private var failed = false

        var body: some View {
            Group {
                if let data, let image = PlatformImage(data: data) {
                    image.swiftUIImage
                        .resizable()
                        .scaledToFit()
                } else if failed {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(WatakeColor.status.danger)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatakeColor.surface.sunken)
            .task(id: page.id) {
                do {
                    data = try await model.loadThumbnailData(for: page)
                } catch {
                    failed = true
                }
            }
        }
    }

    private struct OrganizePageDragPreview: View {
        let page: DocumentPage
        let pageNumber: Int
        let model: OrganizePagesModel

        var body: some View {
            VStack(spacing: WatakeSpacing.xs) {
                OrganizePageImage(page: page, model: model)
                    .frame(width: 112, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md, style: .continuous))
                Text("Page \(pageNumber)")
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.primary)
            }
            .padding(WatakeSpacing.sm)
            .background(WatakeColor.surface.raised)
            .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.lg, style: .continuous))
        }
    }

    private struct PageReorderDropDelegate: DropDelegate {
        let targetPageID: UUID
        @Binding var draggedPageID: UUID?
        let model: OrganizePagesModel
        let reduceMotion: Bool

        func dropEntered(info _: DropInfo) {
            guard let draggedPageID, draggedPageID != targetPageID else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                model.move(pageID: draggedPageID, before: targetPageID)
            }
        }

        func dropUpdated(info _: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info _: DropInfo) -> Bool {
            draggedPageID = nil
            return true
        }
    }
#endif
