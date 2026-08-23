import Foundation
import Testing
@testable import DocumentViewerFeature

@Suite("Document watermarked-copy strip policy")
struct DocumentWatermarkedCopyStripPolicyTests {
    @Test("shows only three newest copies")
    func showsOnlyThreeNewestCopies() {
        let baseDate = Date(timeIntervalSince1970: 1000)
        let copies = (0 ..< 5).map { offset in
            DocumentWatermarkedCopySummary(
                id: UUID(),
                recipientName: "Recipient \(offset)",
                version: offset + 1,
                createdAt: baseDate.addingTimeInterval(TimeInterval(offset))
            )
        }

        let visible = DocumentWatermarkedCopyStripPolicy.visibleCopies(from: copies)

        #expect(visible.count == 3)
        #expect(visible.map(\.version) == [5, 4, 3])
    }

    @Test("empty input stays empty")
    func emptyInputStaysEmpty() {
        #expect(DocumentWatermarkedCopyStripPolicy.visibleCopies(from: []).isEmpty)
    }

    @Test("equal timestamps sort by version then recipient")
    func equalTimestampsSortByVersionThenRecipient() {
        let date = Date(timeIntervalSince1970: 1000)
        let copies = [
            makeSummary(recipient: "Zulu", version: 2, date: date),
            makeSummary(recipient: "Beta", version: 3, date: date),
            makeSummary(recipient: "Alpha", version: 3, date: date),
            makeSummary(recipient: "Older version", version: 1, date: date)
        ]

        let visible = DocumentWatermarkedCopyStripPolicy.visibleCopies(from: copies)

        #expect(visible.map(\.recipientName) == ["Alpha", "Beta", "Zulu"])
    }

    private func makeSummary(
        recipient: String,
        version: Int,
        date: Date
    ) -> DocumentWatermarkedCopySummary {
        DocumentWatermarkedCopySummary(
            id: UUID(),
            recipientName: recipient,
            version: version,
            createdAt: date
        )
    }
}
