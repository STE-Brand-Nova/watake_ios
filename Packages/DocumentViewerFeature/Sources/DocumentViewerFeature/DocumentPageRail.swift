#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain

    /// Ordered page thumbnails. Horizontal in Compact, vertical in Regular/
    /// Expanded, per `RESPONSIVE.md`'s "Document Viewer" section.
    struct DocumentPageRail: View {
        let content: DocumentViewerContent
        let model: DocumentViewerModel
        let axis: Axis

        var body: some View {
            ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                Group {
                    if axis == .horizontal {
                        HStack(spacing: WatakeSpacing.sm) { rows }
                    } else {
                        VStack(spacing: WatakeSpacing.sm) { rows }
                    }
                }
                .padding(WatakeSpacing.sm)
            }
        }

        private var rows: some View {
            ForEach(Array(content.pages.enumerated()), id: \.element.id) { index, page in
                let isSelected = page.id == content.selectedPageID
                Button {
                    model.select(pageID: page.id)
                } label: {
                    DocumentPageThumbnail(page: page, model: model, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(index + 1) of \(content.pages.count)")
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    /// One rail thumbnail. Loads its own asset data independently of the main
    /// preview so the rail never blocks on the selected page's full-size load.
    struct DocumentPageThumbnail: View {
        let page: DocumentPage
        let model: DocumentViewerModel
        let isSelected: Bool

        @State private var data: Data?
        @State private var failed = false

        var body: some View {
            Group {
                if let data, let image = PlatformImage(data: data) {
                    image.swiftUIImage
                        .resizable()
                        .scaledToFill()
                } else if failed {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(WatakeColor.status.danger)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 56, height: 56)
            .background(WatakeColor.surface.sunken)
            .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: WatakeRadius.sm)
                    .strokeBorder(isSelected ? WatakeColor.brand.primary : WatakeColor.border.subtle, lineWidth: isSelected ? 2 : 1)
            }
            .frame(minWidth: 44, minHeight: 44)
            .task(id: page.id) {
                data = nil
                failed = false
                do {
                    data = try await model.loadThumbnailData(for: page)
                } catch {
                    failed = true
                }
            }
        }
    }
#endif
