#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain

    /// Root viewer surface: reopens a saved document by `DocumentID` and shows
    /// its ordered pages. Adapts internally between compact (full-screen +
    /// horizontal thumbnails), regular (thumbnail rail + detail), and expanded
    /// (wider rail + detail) per `RESPONSIVE.md`'s "Document Viewer" section.
    ///
    /// The caller owns `model` and keeps it alive across width-class changes so
    /// the selected document/page is never lost when the shell reflows.
    public struct DocumentViewerView: View {
        @Bindable private var model: DocumentViewerModel

        public init(model: DocumentViewerModel) {
            self.model = model
        }

        public var body: some View {
            GeometryReader { proxy in
                let widthClass = WatakeLayout.widthClass(for: proxy.size.width)
                stateView(widthClass: widthClass)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(WatakeColor.surface.base)
            .task { model.loadIfNeeded() }
        }

        @ViewBuilder
        private func stateView(widthClass: WatakeWidthClass) -> some View {
            switch model.state {
            case .loading:
                ProgressView("Loading document")
                    .accessibilityLabel("Loading document")

            case .empty:
                WatakeEmptyState(
                    systemImage: "doc.questionmark",
                    title: "Document not found.",
                    message: "It may have been moved or deleted."
                )

            case .failure:
                WatakeEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't open this document.",
                    message: "Try again.",
                    actionTitle: "Retry",
                    actionAccessibilityIdentifier: "documentViewer.retry"
                ) {
                    model.retry()
                }

            case .content(let content):
                DocumentViewerContentView(content: content, widthClass: widthClass, model: model)
                    .navigationTitle(content.document.name)
            }
        }
    }

    /// Splits compact vs. regular/expanded per `RESPONSIVE.md`. Regular and
    /// expanded currently share a rail+detail structure; expanded additionally
    /// widens the rail per the shared list-column measurement.
    struct DocumentViewerContentView: View {
        let content: DocumentViewerContent
        let widthClass: WatakeWidthClass
        let model: DocumentViewerModel

        var body: some View {
            switch widthClass {
            case .compact:
                VStack(spacing: 0) {
                    DocumentPagePreview(content: content, model: model)
                        .frame(maxHeight: .infinity)
                    DocumentPageRail(content: content, model: model, axis: .horizontal)
                        .frame(height: 96)
                        .background(WatakeColor.surface.raised)
                }
            case .regular, .expanded:
                HStack(spacing: 0) {
                    DocumentPageRail(content: content, model: model, axis: .vertical)
                        .frame(width: widthClass == .expanded ? 340 : 300)
                        .background(WatakeColor.surface.raised)
                    Divider()
                    DocumentPagePreview(content: content, model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
#endif
