import Foundation
import Testing
@testable import WatakeDomain

@Suite("BulkExportDraft")
struct BulkExportDraftTests {
    // MARK: - Factory & Ordering

    @Test("from(documents:) expands documents into ordered page items")
    func factoryExpansionAndOrdering() {
        let doc1Page1 = makePage(id: fixedUUID(1), index: 1) // reversed index for testing order
        let doc1Page0 = makePage(id: fixedUUID(0), index: 0)
        let doc1 = makeDocument(id: fixedUUID(100), orderIndex: 1, pages: [doc1Page1, doc1Page0])

        let doc0Page0 = makePage(id: fixedUUID(2), index: 0)
        let doc0 = makeDocument(id: fixedUUID(101), orderIndex: 0, pages: [doc0Page0])

        // Act
        let draft = BulkExportDraft.from(documents: [doc1, doc0], outputFilename: "Test")

        // Assert: doc0 first (orderIndex 0), then doc1 (orderIndex 1)
        // Within doc1, page0 (index 0) first, then page1 (index 1)
        #expect(draft.items.count == 3)
        #expect(draft.items[0].id == doc0Page0.id)
        #expect(draft.items[1].id == doc1Page0.id)
        #expect(draft.items[2].id == doc1Page1.id)

        // All included by default.
        // Closure form (not \.isIncluded key path): the #expect macro treats a
        // key-path argument to allSatisfy as a throwing call and fails to
        // compile. swiftformat:disable:next preferKeyPath
        #expect(draft.items.allSatisfy { $0.isIncluded })
        #expect(draft.outputFilename == "Test")
    }

    // MARK: - Include / Exclude

    @Test("toggleInclusion updates page included state")
    func toggleInclusion() {
        var draft = makeDraft(pageCount: 3)
        let pageID = draft.items[1].id

        #expect(draft.items[1].isIncluded == true)

        draft.toggleInclusion(pageID: pageID)
        #expect(draft.items[1].isIncluded == false)
        #expect(draft.includedItems.count == 2)

        draft.toggleInclusion(pageID: pageID)
        #expect(draft.items[1].isIncluded == true)
        #expect(draft.includedItems.count == 3)
    }

    // MARK: - Move Operations

    @Test("moveItems mimics SwiftUI onMove")
    func moveItems() {
        var draft = makeDraft(pageCount: 5)
        let originalIds = draft.items.map(\.id)

        // Move item at index 1 and 2 to index 4 (before 4)
        draft.moveItems(from: IndexSet([1, 2]), to: 4)

        let newIds = draft.items.map(\.id)
        // Expected: 0, 3, 1, 2, 4
        #expect(newIds == [
            originalIds[0],
            originalIds[3],
            originalIds[1],
            originalIds[2],
            originalIds[4]
        ])
    }

    @Test("moveUp shifts item one position earlier")
    func moveUp() {
        var draft = makeDraft(pageCount: 3)
        let id1 = draft.items[1].id

        let newIndex = draft.moveUp(pageID: id1)

        #expect(newIndex == 0)
        #expect(draft.items[0].id == id1)

        // At top, should return nil
        #expect(draft.moveUp(pageID: id1) == nil)
    }

    @Test("moveDown shifts item one position later")
    func moveDown() {
        var draft = makeDraft(pageCount: 3)
        let id1 = draft.items[1].id

        let newIndex = draft.moveDown(pageID: id1)

        #expect(newIndex == 2)
        #expect(draft.items[2].id == id1)

        // At bottom, should return nil
        #expect(draft.moveDown(pageID: id1) == nil)
    }

    // MARK: - Validation

    @Test("validate rejects empty selection")
    func validateEmpty() {
        var draft = makeDraft(pageCount: 1)
        draft.toggleInclusion(pageID: draft.items[0].id)

        #expect(draft.canExport == false)

        expectExportError(.emptyDraft) {
            try draft.validate()
        }
    }

    @Test("validate rejects duplicate page IDs")
    func validateDuplicateIDs() {
        let page = BulkExportDraft.PageItem(id: fixedUUID(1), documentName: "Doc", assetReference: makeAsset())
        let draft = BulkExportDraft(items: [page, page], outputFilename: "Test")

        expectExportError(.duplicatePageIDs) {
            try draft.validate()
        }
    }

    @Test("validate rejects negative margin")
    func validateNegativeMargin() {
        let draft = BulkExportDraft(items: [makeDraft(pageCount: 1).items[0]], outputFilename: "Test", marginPoints: -10)
        expectExportError(.marginTooLarge(marginPoints: -10, availableWidth: 0, availableHeight: 0)) {
            try draft.validate()
        }
    }

    // MARK: - Value Semantics

    @Test("reorder mutates only draft copy")
    func valueSemantics() {
        let draft1 = makeDraft(pageCount: 2)
        var draft2 = draft1

        draft2.moveDown(pageID: draft2.items[0].id)

        #expect(draft1.items[0].id != draft2.items[0].id)
    }

    // MARK: - Filename Sanitization

    @Test("ExportFilenameSanitizer sanitizes filenames correctly")
    func filenameSanitization() {
        #expect(ExportFilenameSanitizer.sanitize("My/File:Name\\Test") == "My_File_Name_Test")
        #expect(ExportFilenameSanitizer.sanitize("  Trimmed  \n") == "Trimmed")
        #expect(ExportFilenameSanitizer.sanitize("Null\0Char") == "NullChar")
        #expect(ExportFilenameSanitizer.sanitize("Café 東京") == "Café 東京")

        // Control chars
        let withControl = "Test\u{08}Name"
        #expect(ExportFilenameSanitizer.sanitize(withControl) == "TestName")

        // Empty fallback
        #expect(ExportFilenameSanitizer.sanitize("   ") == "Watake Export")

        // Length limit
        let longName = String(repeating: "a", count: 150)
        #expect(ExportFilenameSanitizer.sanitize(longName).count == ExportFilenameSanitizer.maxLength)
    }

    // MARK: - Helpers

    private func makeDraft(pageCount: Int) -> BulkExportDraft {
        let items = (0 ..< pageCount).map { index in
            BulkExportDraft.PageItem(
                id: fixedUUID(index),
                documentName: "Doc \(index)",
                assetReference: makeAsset()
            )
        }
        return BulkExportDraft(items: items, outputFilename: "Test Draft")
    }

    private func fixedUUID(_ value: Int) -> UUID {
        let byte = UInt8(value)
        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

    private func makeAsset() -> AssetReference {
        AssetReference(id: fixedUUID(99), relativePath: "test.jpg", sha256Hex: String(repeating: "a", count: 64), byteSize: 1000)
    }

    private func makePage(id: UUID, index: Int) -> DocumentPage {
        DocumentPage(id: id, index: index, source: makeAsset())
    }

    private func makeDocument(id: UUID, orderIndex: Int, pages: [DocumentPage]) -> StoredDocument {
        StoredDocument(
            id: id,
            folderId: fixedUUID(100),
            name: "Doc",
            createdAt: Date(),
            updatedAt: Date(),
            orderIndex: orderIndex,
            pages: pages
        )
    }

    private func expectExportError(_ expected: ExportError, body: () throws -> Void) {
        do {
            try body()
            Issue.record("Expected \(expected)")
        } catch let error as ExportError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected \(expected), got \(error)")
        }
    }
}
