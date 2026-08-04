import DesignSystem
import Foundation
import Testing
import WatakeDomain
@testable import CaptureFeature

@MainActor
struct CaptureFeatureTests {
    private func makeSamplePage(
        id: UUID = UUID(),
        source: String = "sample-source-data",
        rectified: String? = nil,
        rotation: Int = 0
    ) -> CaptureReviewPage {
        CaptureReviewPage(
            id: id,
            sourceData: Data(source.utf8),
            rectifiedData: rectified.map { Data($0.utf8) },
            rotationDegrees: rotation
        )
    }

    @Test
    func testSelectPage() {
        let page1 = makeSamplePage()
        let page2 = makeSamplePage()
        let state = CaptureReviewState(pages: [page1, page2], selectedIndex: 0)

        #expect(state.selectedPage?.id == page1.id)

        state.selectPage(at: 1)
        #expect(state.selectedIndex == 1)
        #expect(state.selectedPage?.id == page2.id)

        // Invalid index ignored
        state.selectPage(at: 99)
        #expect(state.selectedIndex == 1)
    }

    @Test
    func rotateSelectedPageNonDestructive() {
        let page1 = makeSamplePage(rotation: 0)
        let state = CaptureReviewState(pages: [page1], selectedIndex: 0)

        #expect(state.selectedPage?.rotationDegrees == 0)

        state.rotateSelectedPage()
        #expect(state.selectedPage?.rotationDegrees == 90)

        state.rotateSelectedPage()
        #expect(state.selectedPage?.rotationDegrees == 180)

        state.rotateSelectedPage()
        #expect(state.selectedPage?.rotationDegrees == 270)

        state.rotateSelectedPage()
        #expect(state.selectedPage?.rotationDegrees == 0)

        // Source data remains intact
        #expect(state.selectedPage?.sourceData == Data("sample-source-data".utf8))
    }

    @Test
    func rotationCompletesAfterPreviewUpdateNoDoubleRotation() async throws {
        let page1 = makeSamplePage(rotation: 0)
        let state = CaptureReviewState(pages: [page1], selectedIndex: 0)
        let rectifier = SlowRectifier()

        #expect(state.selectedPage?.visualRotationDegrees == 0)

        // Trigger rotation with async rectifier
        state.rotateSelectedPage(via: rectifier)

        // Immediately after tapping rotate, rotationDegrees is 90, rectifiedData is nil, visualRotationDegrees is 90
        #expect(state.selectedPage?.rotationDegrees == 90)
        #expect(state.selectedPage?.rectifiedData == nil)
        #expect(state.selectedPage?.visualRotationDegrees == 90)

        // Wait for async rectification to complete
        try await Task.sleep(nanoseconds: 150_000_000)

        // After rectification completes, rectifiedData is non-nil (with rotation baked in), visualRotationDegrees is 0 (no double rotation)
        #expect(state.selectedPage?.rotationDegrees == 90)
        #expect(state.selectedPage?.rectifiedData != nil)
        #expect(state.selectedPage?.visualRotationDegrees == 0)
    }

    @Test
    func saveAwaitsInFlightProcessingTasksBeforeSaving() async {
        let page1 = makeSamplePage(rotation: 0)
        let folderID = UUID()
        let state = CaptureReviewState(
            pages: [page1],
            selectedIndex: 0,
            saveDestinationFolderID: folderID,
            documentName: "Rotated Document"
        )
        let rectifier = SlowRectifier()
        let saver = CapturingSaver()

        // Start async rotation task (clears rectifiedData to nil while task runs)
        state.rotateSelectedPage(via: rectifier)
        #expect(state.isProcessing)
        #expect(state.selectedPage?.rectifiedData == nil)

        // Save immediately while processing task is still in-flight
        var wasSaved = false
        await state.save(via: saver) {
            wasSaved = true
        }

        #expect(wasSaved)
        #expect(!state.isProcessing)
        // Verify that saver received the completed rectifiedJPEG output, not nil
        #expect(saver.savedPages.first?.rectifiedJPEG == Data("slow-rectified-output".utf8))
    }

    @Test
    func deleteSelectedPageAdjustsIndexAndHandlesEmpty() {
        let page1 = makeSamplePage()
        let page2 = makeSamplePage()
        let page3 = makeSamplePage()
        let state = CaptureReviewState(pages: [page1, page2, page3], selectedIndex: 2)

        // Delete last page (index 2) -> index becomes 1
        state.deleteSelectedPage()
        #expect(state.pages.count == 2)
        #expect(state.selectedIndex == 1)
        #expect(state.selectedPage?.id == page2.id)

        // Delete middle page (index 1) -> index becomes 0
        state.deleteSelectedPage()
        #expect(state.pages.count == 1)
        #expect(state.selectedIndex == 0)
        #expect(state.selectedPage?.id == page1.id)

        // Delete final page -> empty review state
        state.deleteSelectedPage()
        #expect(state.pages.isEmpty)
        #expect(state.selectedIndex == 0)
        #expect(state.selectedPage == nil)
    }

    @Test
    func retakeClearsPagesAndState() {
        let page1 = makeSamplePage()
        let state = CaptureReviewState(
            pages: [page1],
            selectedIndex: 0,
            isEditingCrop: true,
            isShowingSaveDestination: true,
            saveError: "Previous error"
        )

        state.retake()

        #expect(state.pages.isEmpty)
        #expect(state.selectedIndex == 0)
        #expect(!state.isEditingCrop)
        #expect(!state.isShowingSaveDestination)
        #expect(state.saveError == nil)
    }

    @Test
    func inFlightCropTaskIsCancelledWhenPageDeletedOrRetaken() async throws {
        let page1 = makeSamplePage()
        let state = CaptureReviewState(pages: [page1], selectedIndex: 0)

        // Apply crop which starts slow async rectification task
        state.applyCrop(
            quadrilateral: CropQuadrilateral(
                topLeft: NormalizedPoint(x: 0.1, y: 0.9),
                topRight: NormalizedPoint(x: 0.9, y: 0.9),
                bottomRight: NormalizedPoint(x: 0.9, y: 0.1),
                bottomLeft: NormalizedPoint(x: 0.1, y: 0.1)
            ),
            via: SlowRectifier()
        )

        // Immediately delete selected page
        state.deleteSelectedPage()
        #expect(state.pages.isEmpty)

        // Wait for slow task duration
        try await Task.sleep(nanoseconds: 150_000_000)

        // Verify stale task did not recreate or corrupt state
        #expect(state.pages.isEmpty)
    }

    @Test
    func statePreservationAcrossCompactAndRegularReflow() {
        let page1 = makeSamplePage(rotation: 90)
        let page2 = makeSamplePage(rotation: 180)
        let folderID = UUID()
        let state = CaptureReviewState(
            pages: [page1, page2],
            selectedIndex: 1,
            grouping: .separateDocuments,
            saveDestinationFolderID: folderID,
            documentName: "Custom Document Name",
            newFolderName: "New Folder Name"
        )

        // Simulate Compact evaluation
        #expect(state.pages.count == 2)
        #expect(state.selectedIndex == 1)
        #expect(state.selectedPage?.rotationDegrees == 180)
        #expect(state.grouping == .separateDocuments)
        #expect(state.saveDestinationFolderID == folderID)
        #expect(state.documentName == "Custom Document Name")

        // Mutate in Compact
        state.rotateSelectedPage()
        #expect(state.selectedPage?.rotationDegrees == 270)

        // Transition to Regular (state object is retained)
        #expect(state.pages.count == 2)
        #expect(state.selectedIndex == 1)
        #expect(state.selectedPage?.rotationDegrees == 270)
        #expect(state.grouping == .separateDocuments)
        #expect(state.saveDestinationFolderID == folderID)
        #expect(state.documentName == "Custom Document Name")
    }

    @Test
    func saveFailureRetainsReviewPagesAndInputs() async {
        let page1 = makeSamplePage()
        let folderID = UUID()
        let state = CaptureReviewState(
            pages: [page1],
            selectedIndex: 0,
            saveDestinationFolderID: folderID,
            documentName: "Important Invoice"
        )

        var wasSaved = false
        await state.save(via: FailingSaver()) {
            wasSaved = true
        }

        #expect(!wasSaved)
        #expect(state.saveError != nil)
        #expect(state.pages.count == 1)
        #expect(state.selectedIndex == 0)
        #expect(state.saveDestinationFolderID == folderID)
        #expect(state.documentName == "Important Invoice")
    }

    @Test
    func saveRejectsConcurrentDuplicateSubmissions() async {
        let folderID = UUID()
        let state = CaptureReviewState(
            pages: [makeSamplePage()],
            saveDestinationFolderID: folderID
        )
        let saver = DelayedCountingSaver()

        let firstSave = Task { @MainActor in
            await state.save(via: saver) {}
        }
        let secondSave = Task { @MainActor in
            await state.save(via: saver) {}
        }

        await firstSave.value
        await secondSave.value

        let saveCallCount = await saver.saveCallCount
        #expect(saveCallCount == 1)
        #expect(!state.isSaving)
    }

    @Test
    func twoPaneMinWidthDerivesFromRenderedLayoutRequirements() {
        let expected = CaptureReviewLayoutPolicy.mainPaneMinWidth
            + CaptureReviewLayoutPolicy.trailingPanelWidth
            + CaptureReviewLayoutPolicy.paneSpacing
            + (CaptureReviewLayoutPolicy.outerPaddingPerSide * 2)

        #expect(CaptureReviewLayoutPolicy.twoPaneMinWidth == expected)
        #expect(CaptureReviewView.twoPaneMinWidth == expected)
        // Documents the current concrete point value so a silent token-scale
        // change is caught explicitly rather than only through the formula.
        #expect(CaptureReviewLayoutPolicy.twoPaneMinWidth == 860)
    }

    @Test
    func usesTwoPaneBelowAndAtTrueMinimumWidth() {
        let minWidth = CaptureReviewLayoutPolicy.twoPaneMinWidth

        #expect(!CaptureReviewLayoutPolicy.usesTwoPane(forWidth: minWidth - 1))
        #expect(CaptureReviewLayoutPolicy.usesTwoPane(forWidth: minWidth))
    }

    @Test
    func rectificationFailureClearsInFlightStateInsteadOfLeaking() async throws {
        let page1 = makeSamplePage(rotation: 0)
        let state = CaptureReviewState(pages: [page1], selectedIndex: 0)
        let rectifier = FailingRectifier()

        state.rotateSelectedPage(via: rectifier)
        #expect(state.isProcessing)

        try await Task.sleep(nanoseconds: 100_000_000)

        // A failed rectification must clear its in-flight entry, not leave
        // isProcessing (and therefore Save) stuck forever.
        #expect(!state.isProcessing)
        #expect(state.selectedPage?.rectifiedData == nil)
    }

    @Test
    func saveFailsSafelyWhenEditedPageRectificationFails() async {
        let page1 = makeSamplePage(rotation: 0)
        let folderID = UUID()
        let state = CaptureReviewState(
            pages: [page1],
            selectedIndex: 0,
            saveDestinationFolderID: folderID
        )
        let rectifier = FailingRectifier()
        let saver = CapturingSaver()

        state.rotateSelectedPage(via: rectifier)

        var wasSaved = false
        await state.save(via: saver) {
            wasSaved = true
        }

        #expect(!wasSaved)
        #expect(state.saveError != nil)
        #expect(saver.savedPages.isEmpty)
        // The unmodified source must never be silently persisted in place of
        // a rotation/crop that failed to process.
        #expect(state.selectedPage?.rectifiedData == nil)
        #expect(!state.isSaving)
    }

    @Test
    func saveAwaitsTasksStartedWhileAlreadySaving() async {
        let page1 = makeSamplePage(rotation: 0)
        let folderID = UUID()
        let state = CaptureReviewState(
            pages: [page1],
            selectedIndex: 0,
            saveDestinationFolderID: folderID
        )
        let rectifier = SlowRectifier()
        let saver = CapturingSaver()

        // Start a first slow task, then begin save while it is still running.
        state.rotateSelectedPage(via: rectifier)

        let saveTask = Task {
            await state.save(via: saver) {}
        }

        // While save() is awaiting the first task, trigger a second edit that
        // starts a brand-new in-flight task after save's initial snapshot.
        try? await Task.sleep(nanoseconds: 20_000_000)
        state.rotateSelectedPage(via: rectifier)

        await saveTask.value

        // Save must not race past the second task with stale/nil data.
        #expect(saver.savedPages.first?.rectifiedJPEG == Data("slow-rectified-output".utf8))
        #expect(!state.isProcessing)
    }

    @Test
    func saveAbortsSafelyIfPagesClearedDuringInFlightAwait() async {
        let page1 = makeSamplePage(rotation: 0)
        let folderID = UUID()
        let state = CaptureReviewState(
            pages: [page1],
            selectedIndex: 0,
            saveDestinationFolderID: folderID
        )
        let rectifier = SlowRectifier()
        let saver = CapturingSaver()

        state.rotateSelectedPage(via: rectifier)

        var wasSaved = false
        let saveTask = Task {
            await state.save(via: saver) { wasSaved = true }
        }

        // Retake clears pages while save() is still awaiting the in-flight task.
        try? await Task.sleep(nanoseconds: 20_000_000)
        state.retake()

        await saveTask.value

        #expect(!wasSaved)
        #expect(saver.savedPages.isEmpty)
        #expect(state.pages.isEmpty)
    }
}

private struct SlowRectifier: DocumentRectifying {
    func detect(in jpegData: Data) async -> RectificationResult {
        RectificationResult(quadrilateral: .unit, isDetectionConfident: true)
    }

    func rectify(jpegData: Data, quadrilateral: CropQuadrilateral, rotationDegrees: Int) async -> Data? {
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        return Data("slow-rectified-output".utf8)
    }
}

private struct FailingRectifier: DocumentRectifying {
    func detect(in jpegData: Data) async -> RectificationResult {
        RectificationResult(quadrilateral: .unit, isDetectionConfident: true)
    }

    func rectify(jpegData: Data, quadrilateral: CropQuadrilateral, rotationDegrees: Int) async -> Data? {
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        return nil
    }
}

private struct MockSaveError: Error {}

private struct FailingSaver: CaptureSaving {
    func save(pages: [ImportedPage], grouping: GalleryGrouping, folderID: UUID, name: String) async throws -> [StoredDocument] {
        throw MockSaveError()
    }
}

private final class CapturingSaver: CaptureSaving, @unchecked Sendable {
    var savedPages: [ImportedPage] = []
    func save(pages: [ImportedPage], grouping: GalleryGrouping, folderID: UUID, name: String) async throws -> [StoredDocument] {
        savedPages = pages
        return []
    }
}

private actor DelayedCountingSaver: CaptureSaving {
    private(set) var saveCallCount = 0

    func save(pages: [ImportedPage], grouping: GalleryGrouping, folderID: UUID, name: String) async throws -> [StoredDocument] {
        saveCallCount += 1
        try await Task.sleep(for: .milliseconds(100))
        return []
    }
}
