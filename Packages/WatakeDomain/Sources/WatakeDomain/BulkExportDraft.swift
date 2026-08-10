import Foundation

/// Ephemeral, ordered page list for a single bulk export operation.
///
/// Never persisted or stored in SwiftData. Reordering, include/exclude, and
/// settings mutations affect only this draft — library `Document.orderIndex`
/// and `DocumentPage.index` are never written.
///
/// The draft is value-typed and suitable for unit tests. It captures ordered
/// page items, output settings, and enough metadata for the UI and renderer.
public struct BulkExportDraft: Equatable, Sendable {
    /// One page in the export draft. Carries identity, display metadata, and
    /// the immutable asset reference for rendering.
    public struct PageItem: Identifiable, Equatable, Sendable {
        /// The `DocumentPage.id` this item represents.
        public let id: UUID
        /// Display-only document name, for the review UI. Not logged.
        public let documentName: String
        /// 0-based page index in the source document.
        public let sourcePageIndex: Int
        /// Total pages in the source document.
        public let sourceTotalPages: Int
        /// Best-available asset reference for rendering (rectified > source).
        public let assetReference: AssetReference
        /// OCR block geometry, used only when the OCR text layer is enabled.
        public let ocrBlocks: [OCRBlock]
        /// Whether this page is included in the export. Toggled by the user.
        public var isIncluded: Bool

        public init(
            id: UUID,
            documentName: String,
            sourcePageIndex: Int = 0,
            sourceTotalPages: Int = 1,
            assetReference: AssetReference,
            ocrBlocks: [OCRBlock] = [],
            isIncluded: Bool = true
        ) {
            self.id = id
            self.documentName = documentName
            self.sourcePageIndex = sourcePageIndex
            self.sourceTotalPages = sourceTotalPages
            self.assetReference = assetReference
            self.ocrBlocks = ocrBlocks
            self.isIncluded = isIncluded
        }
    }

    /// Ordered page items. Reorder operations mutate this array.
    public private(set) var items: [PageItem]
    /// Suggested output filename (sanitized before use).
    public var outputFilename: String
    /// Target page size.
    public var pageSize: ExportPageSize
    /// Fit or fill mode.
    public var fitMode: ExportFitMode
    /// Margin in PDF points. Must be non-negative.
    public var marginPoints: Double

    /// Pages included in the export, in draft order.
    public var includedItems: [PageItem] {
        items.filter(\.isIncluded)
    }

    /// Whether the draft has at least one included page.
    public var canExport: Bool {
        !includedItems.isEmpty
    }

    public init(
        items: [PageItem],
        outputFilename: String,
        pageSize: ExportPageSize = .a4,
        fitMode: ExportFitMode = .fit,
        marginPoints: Double = 0
    ) {
        self.items = items
        self.outputFilename = outputFilename
        self.pageSize = pageSize
        self.fitMode = fitMode
        self.marginPoints = marginPoints
    }

    /// Validates the draft before export.
    public func validate() throws {
        guard canExport else { throw ExportError.emptyDraft }
        let ids = items.map(\.id)
        guard Set(ids).count == ids.count else { throw ExportError.duplicatePageIDs }
        guard marginPoints >= 0 else {
            throw ExportError.marginTooLarge(marginPoints: marginPoints, availableWidth: 0, availableHeight: 0)
        }
    }

    // MARK: - Draft Manipulation

    /// Toggles inclusion of a page by ID. No-op if the page is not in the draft.
    public mutating func toggleInclusion(pageID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == pageID }) else { return }
        items[index].isIncluded.toggle()
    }

    /// Moves items at the given offsets to a new position.
    ///
    /// Semantics match SwiftUI's `onMove` behaviour: `destination` is the index
    /// in the *original* array before the source elements are removed, and the
    /// moved elements are inserted at the position that index points to after
    /// removal.
    public mutating func moveItems(from source: IndexSet, to destination: Int) {
        // Gather the elements to move, preserving their relative order.
        let moving = source.map { items[$0] }
        // Remove them in reverse so earlier indices remain valid.
        for index in source.sorted().reversed() {
            items.remove(at: index)
        }
        // Adjust destination for removed elements that were before it.
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        let insertAt = min(adjustedDestination, items.count)
        items.insert(contentsOf: moving, at: insertAt)
    }

    /// Moves a page up by one position. Returns the new index, or nil if already at top.
    @discardableResult
    public mutating func moveUp(pageID: UUID) -> Int? {
        guard let index = items.firstIndex(where: { $0.id == pageID }),
              index > 0 else { return nil }
        items.swapAt(index, index - 1)
        return index - 1
    }

    /// Moves a page down by one position. Returns the new index, or nil if already at bottom.
    @discardableResult
    public mutating func moveDown(pageID: UUID) -> Int? {
        guard let index = items.firstIndex(where: { $0.id == pageID }),
              index < items.count - 1 else { return nil }
        items.swapAt(index, index + 1)
        return index + 1
    }

    // MARK: - Factory

    /// Creates a draft from selected documents, expanding pages in document
    /// order × page index order. Uses `bestAvailableAsset` for each page.
    public static func from(
        documents: [StoredDocument],
        outputFilename: String
    ) -> BulkExportDraft {
        var pageItems: [PageItem] = []
        let sorted = documents.sorted { $0.orderIndex < $1.orderIndex }
        for document in sorted {
            let sortedPages = document.pages.sorted { $0.index < $1.index }
            for page in sortedPages {
                let bestAsset = page.rectified ?? page.source
                let item = PageItem(
                    id: page.id,
                    documentName: document.name,
                    sourcePageIndex: page.index,
                    sourceTotalPages: sortedPages.count,
                    assetReference: bestAsset,
                    ocrBlocks: page.ocrBlocks,
                    isIncluded: true
                )
                pageItems.append(item)
            }
        }
        return BulkExportDraft(items: pageItems, outputFilename: outputFilename)
    }
}
