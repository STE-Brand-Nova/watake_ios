#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain

    /// Full-page preview of the currently selected page, with a "Page N of M"
    /// label and a privacy-safe error/retry path when the asset can't be shown.
    struct DocumentPagePreview: View {
        let content: DocumentViewerContent
        let model: DocumentViewerModel

        var body: some View {
            VStack(spacing: WatakeSpacing.sm) {
                Group {
                    if content.selectedPage != nil, let index = content.selectedIndex {
                        pageContent(pageNumber: index + 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let index = content.selectedIndex {
                    Text("Page \(index + 1) of \(content.pages.count)")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.secondary)
                }
            }
            .padding(WatakeSpacing.md)
            .onKeyPress(.leftArrow) { selectAdjacent(offset: -1) }
            .onKeyPress(.rightArrow) { selectAdjacent(offset: 1) }
        }

        @ViewBuilder
        private func pageContent(pageNumber: Int) -> some View {
            switch content.pageAsset {
            case .loading:
                ProgressView()
                    .accessibilityLabel("Loading page \(pageNumber) of \(content.pages.count)")

            case .loaded(let data):
                if let image = PlatformImage(data: data) {
                    image.swiftUIImage
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(
                            "Page \(pageNumber) of \(content.pages.count)"
                                + (content.isPageAssetRectified ? "" : ", original scan")
                        )
                } else {
                    unreadableState
                }

            case .failure:
                unreadableState
            }
        }

        private var unreadableState: some View {
            VStack(spacing: WatakeSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(WatakeColor.status.danger)
                    .accessibilityHidden(true)
                Text("This page couldn't be opened.")
                    .watakeType(.body)
                    .foregroundStyle(WatakeColor.text.secondary)
                WatakeButton("Retry", variant: .secondary, accessibilityIdentifier: "documentViewer.retryPage") {
                    model.retry()
                }
            }
        }

        private func selectAdjacent(offset: Int) -> KeyPress.Result {
            guard let index = content.selectedIndex else { return .ignored }
            let target = index + offset
            guard content.pages.indices.contains(target) else { return .ignored }
            model.select(pageID: content.pages[target].id)
            return .handled
        }
    }
#endif
