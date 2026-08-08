import DesignSystem
import DocumentSearchFeature
import SwiftUI
import WatakeDomain

/// Search presentation only. Query evaluation, debouncing, cancellation, and
/// privacy-safe failures live in `DocumentSearchModel`; navigation stays in
/// the app shell through `onOpen`.
struct SearchView: View {
    @Bindable var model: DocumentSearchModel
    let onOpen: (ArchiveSearchResult) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, WatakeSpacing.md)
                .padding(.vertical, WatakeSpacing.sm)

            content
        }
        .background(WatakeColor.surface.base)
        .navigationTitle("Search")
        .onDisappear(perform: onDismiss)
        .watakeAccessibilityIdentifier("search.archive")
    }

    private var searchField: some View {
        HStack(spacing: WatakeSpacing.xs) {
            TextField("Search archive", text: queryBinding)
                .textFieldStyle(.watakeSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Search archive")

            if !model.query.isEmpty {
                Button("Clear") { model.updateQuery("") }
                    .buttonStyle(.plain)
                    .foregroundStyle(WatakeColor.brand.primary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint("Clears search query")
            }
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { model.query },
            set: { model.updateQuery($0) }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .emptyQuery:
            centeredState(
                systemImage: "magnifyingglass",
                title: "Search your archive.",
                message: "Find folders, document names, tags, and extracted text."
            )
        case .loading:
            ProgressView("Searching archive")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Searching archive")
        case .results(let results):
            List(results) { result in
                Button {
                    if let current = model.open(result) {
                        onOpen(current)
                    }
                } label: {
                    SearchResultRow(result: result)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityHint(resultHint(result))
            }
            .listStyle(.plain)
        case .noResults:
            centeredState(
                systemImage: "doc.text.magnifyingglass",
                title: "No matches.",
                message: "Try a shorter query or a different tag."
            )
        case .failure:
            WatakeEmptyState(
                systemImage: "exclamationmark.triangle",
                title: "Search unavailable.",
                message: "Your archive remains private. Try again.",
                actionTitle: "Retry",
                action: { model.retry() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func centeredState(systemImage: String, title: String, message: String) -> some View {
        WatakeEmptyState(systemImage: systemImage, title: title, message: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultHint(_ result: ArchiveSearchResult) -> String {
        switch result {
        case .folder:
            "Opens folder"
        case .document:
            "Opens document"
        }
    }
}

private struct SearchResultRow: View {
    let result: ArchiveSearchResult

    var body: some View {
        HStack(spacing: WatakeSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(WatakeColor.text.secondary)
                .frame(minWidth: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
                Text(result.displayName)
                    .watakeType(.bodyEmphasis)
                    .foregroundStyle(WatakeColor.text.primary)
                    .lineLimit(2)
                Text(kindLabel)
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.secondary)
                if case .document(let document) = result {
                    MatchCategoryLabels(categories: document.matchCategories)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(WatakeColor.text.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var systemImage: String {
        switch result {
        case .folder: "folder"
        case .document: "doc.text"
        }
    }

    private var kindLabel: String {
        switch result {
        case .folder: "Folder"
        case .document: "Document"
        }
    }

    private var accessibilityLabel: String {
        switch result {
        case .folder(let folder): "Folder, \(folder.name)"
        case .document(let document): "Document, \(document.name), \(matchDescription(document.matchCategories))"
        }
    }

    private func matchDescription(_ categories: Set<DocumentSearchMatchCategory>) -> String {
        categories
            .sorted { $0.rawValue < $1.rawValue }
            .map { "\($0.rawValue) match" }
            .joined(separator: ", ")
    }
}

private struct MatchCategoryLabels: View {
    let categories: Set<DocumentSearchMatchCategory>

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WatakeSpacing.xxs) { labels }
            FlowLayout(spacing: WatakeSpacing.xxs) { labels }
        }
        .accessibilityHidden(true)
    }

    private var labels: some View {
        ForEach(categories.sorted { $0.rawValue < $1.rawValue }, id: \.self) { category in
            Text(label(for: category))
                .watakeType(.caption)
                .foregroundStyle(WatakeColor.brand.primary)
                .padding(.horizontal, WatakeSpacing.xs)
                .padding(.vertical, WatakeSpacing.xxs)
                .background(WatakeColor.surface.sunken)
                .clipShape(Capsule())
        }
    }

    private func label(for category: DocumentSearchMatchCategory) -> String {
        switch category {
        case .name: "Name"
        case .tag: "Tag"
        case .ocr: "OCR"
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for placement in layout(proposal: proposal, subviews: subviews).placements {
            subviews[placement.index].place(
                at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, placements: [(index: Int, origin: CGPoint)]) {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var horizontalOffset: CGFloat = 0
        var verticalOffset: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        var placements: [(Int, CGPoint)] = []

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if horizontalOffset > 0, horizontalOffset + size.width > availableWidth {
                horizontalOffset = 0
                verticalOffset += rowHeight + spacing
                rowHeight = 0
            }
            placements.append((index, CGPoint(x: horizontalOffset, y: verticalOffset)))
            horizontalOffset += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, horizontalOffset - spacing)
        }
        return (CGSize(width: maxWidth, height: verticalOffset + rowHeight), placements)
    }
}
