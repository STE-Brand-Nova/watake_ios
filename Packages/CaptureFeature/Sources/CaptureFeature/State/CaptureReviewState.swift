import Foundation
import Observation
import WatakeDomain

public struct AutoAdjustmentSummary: Equatable {
    public let adjustedPageCount: Int
    public let manualReviewPageCount: Int

    public init(adjustedPageCount: Int, manualReviewPageCount: Int) {
        self.adjustedPageCount = adjustedPageCount
        self.manualReviewPageCount = manualReviewPageCount
    }

    public var message: String {
        switch (adjustedPageCount, manualReviewPageCount) {
        case (0, _):
            "No safe document boundary found. Adjust the yellow pages manually."
        case (_, 0):
            "Auto-adjusted \(adjustedPageCount) \(pageNoun(for: adjustedPageCount)) conservatively."
        default:
            partialResultMessage
        }
    }

    public var needsManualReview: Bool {
        manualReviewPageCount > 0
    }

    private func pageNoun(for count: Int) -> String {
        count == 1 ? "page" : "pages"
    }

    private var partialResultMessage: String {
        "Auto-adjusted \(adjustedPageCount) \(pageNoun(for: adjustedPageCount)); "
            + "\(manualReviewPageCount) still need manual corners."
    }
}

@MainActor
@Observable
public final class CaptureReviewState {
    public var pages: [CaptureReviewPage]
    public var selectedIndex: Int
    public var grouping: GalleryGrouping
    public var isEditingCrop: Bool
    public var isShowingSaveDestination: Bool
    public var saveDestinationFolderID: UUID?
    public var documentName: String
    public var newFolderName: String
    public var saveError: String?
    public var isSaving: Bool
    public private(set) var autoAdjustmentSummary: AutoAdjustmentSummary?

    /// Task revision counter per page ID to prevent stale async tasks from overwriting state.
    private var taskRevisions: [UUID: Int] = [:]

    /// Active in-flight processing tasks per page ID for explicit cancellation.
    private var inFlightTasks: [UUID: Task<Void, Never>] = [:]
    private var autoAdjustmentSessionID: UUID?
    private var pendingAutoAdjustmentPageIDs: Set<UUID> = []
    private var autoAdjustedPageCount = 0

    public init(
        pages: [CaptureReviewPage] = [],
        selectedIndex: Int = 0,
        grouping: GalleryGrouping = .oneDocument,
        isEditingCrop: Bool = false,
        isShowingSaveDestination: Bool = false,
        saveDestinationFolderID: UUID? = nil,
        documentName: String = "Document",
        newFolderName: String = "",
        saveError: String? = nil,
        isSaving: Bool = false,
        autoAdjustmentSummary: AutoAdjustmentSummary? = nil
    ) {
        self.pages = pages
        self.selectedIndex = selectedIndex
        self.grouping = grouping
        self.isEditingCrop = isEditingCrop
        self.isShowingSaveDestination = isShowingSaveDestination
        self.saveDestinationFolderID = saveDestinationFolderID
        self.documentName = documentName
        self.newFolderName = newFolderName
        self.saveError = saveError
        self.isSaving = isSaving
        self.autoAdjustmentSummary = autoAdjustmentSummary
    }

    /// Whether any crop/rectification/rotation processing task is currently running in-flight.
    public var isProcessing: Bool {
        !inFlightTasks.isEmpty
    }

    public var selectedPage: CaptureReviewPage? {
        guard pages.indices.contains(selectedIndex) else { return nil }
        return pages[selectedIndex]
    }

    public var uncertainPageCount: Int {
        pages.count(where: \.detectionUncertain)
    }

    public func selectPage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        selectedIndex = index
    }

    public func rotateSelectedPage(via rectifier: (any DocumentRectifying)? = nil) {
        guard pages.indices.contains(selectedIndex) else { return }
        var page = pages[selectedIndex]
        page.rotationDegrees = (page.rotationDegrees + 90) % 360
        page.rectifiedData = nil // Reset rectifiedData so visual rotation renders immediately on sourceData
        pages[selectedIndex] = page
        recomputeRectified(for: page.id, via: rectifier)
    }

    public func applyCrop(quadrilateral: CropQuadrilateral, via rectifier: (any DocumentRectifying)? = nil) {
        guard pages.indices.contains(selectedIndex), quadrilateral.isValid else { return }
        var page = pages[selectedIndex]
        page.cropQuadrilateral = quadrilateral
        page.detectionUncertain = false
        page.wasAutoCropAdjusted = false
        page.rectifiedData = nil // Reset rectifiedData while async crop task runs
        pages[selectedIndex] = page
        recomputeRectified(for: page.id, via: rectifier)
    }

    /// Re-runs detection for every uncertain import. Only candidates that meet
    /// the conservative confidence threshold receive an outward safety margin;
    /// ambiguous pages remain marked for manual review.
    public func autoAdjustUncertainPages(via rectifier: any DocumentRectifying) {
        guard !isSaving else { return }
        let pageIDs = pages.lazy.filter(\.detectionUncertain).map(\.id)
        guard !pageIDs.isEmpty else { return }

        for pageID in pageIDs {
            cancelInFlightTask(for: pageID)
        }

        let sessionID = UUID()
        autoAdjustmentSessionID = sessionID
        pendingAutoAdjustmentPageIDs = Set(pageIDs)
        autoAdjustedPageCount = 0
        autoAdjustmentSummary = nil
        for pageID in pageIDs {
            autoAdjust(pageID: pageID, sessionID: sessionID, via: rectifier)
        }
    }

    public func deleteSelectedPage() {
        guard pages.indices.contains(selectedIndex) else { return }
        let pageID = pages[selectedIndex].id
        cancelInFlightTask(for: pageID)
        pages.remove(at: selectedIndex)
        if pages.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= pages.count {
            selectedIndex = pages.count - 1
        }
    }

    public func retake() {
        for page in pages {
            cancelInFlightTask(for: page.id)
        }
        pages = []
        selectedIndex = 0
        isEditingCrop = false
        isShowingSaveDestination = false
        saveError = nil
    }

    public func save(
        via saver: any CaptureSaving,
        onSuccess: @escaping () -> Void
    ) async {
        guard !isSaving else { return }
        guard let saveDestinationFolderID else {
            saveError = "Target folder is required."
            return
        }
        guard !pages.isEmpty else {
            saveError = "No pages to save."
            return
        }

        isSaving = true
        saveError = nil

        await awaitAllInFlightTasks()

        // Retake/delete may have run while the tasks above were in flight.
        guard !pages.isEmpty else {
            isSaving = false
            saveError = "No pages to save."
            return
        }

        guard !hasUnresolvedEdit else {
            isSaving = false
            saveError = "Some pages could not finish processing. Adjust corners or rotate again, then retry saving."
            return
        }

        let importedPages = pages.map { page in
            ImportedPage(
                sourceData: page.sourceData,
                sourceMediaType: page.sourceMediaType,
                sourceFileExtension: page.sourceFileExtension,
                rectifiedJPEG: page.rectifiedData
            )
        }

        do {
            _ = try await saver.save(
                pages: importedPages,
                grouping: grouping,
                folderID: saveDestinationFolderID,
                name: documentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Document" : documentName
            )
            isSaving = false
            onSuccess()
        } catch is CancellationError {
            isSaving = false
        } catch {
            isSaving = false
            saveError = "Could not save capture. Review pages remain available to retry."
        }
    }

    // MARK: - Async Task & Cancellation Tracking

    /// Whether a page the user cropped or rotated is still missing rectified
    /// data after all in-flight tasks finish. That only happens when the
    /// rectifier failed, and saving must never silently substitute the
    /// unmodified source for a requested edit.
    private var hasUnresolvedEdit: Bool {
        pages.contains { page in
            let wasEdited = page.cropQuadrilateral != nil || page.rotationDegrees != 0
            return wasEdited && page.rectifiedData == nil
        }
    }

    /// Awaits every in-flight task, re-checking after each pass: a rapid edit
    /// made while this save is already waiting starts a new task that a
    /// one-shot snapshot would miss, letting save race past it with stale data.
    private func awaitAllInFlightTasks() async {
        while !inFlightTasks.isEmpty {
            let tasksToAwait = Array(inFlightTasks.values)
            for task in tasksToAwait {
                _ = await task.value
            }
        }
    }

    private func cancelInFlightTask(for pageID: UUID) {
        taskRevisions[pageID] = (taskRevisions[pageID] ?? 0) + 1
        inFlightTasks[pageID]?.cancel()
        inFlightTasks.removeValue(forKey: pageID)
    }

    private func recomputeRectified(for pageID: UUID, via rectifier: (any DocumentRectifying)?) {
        guard let rectifier else { return }
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let page = pages[index]

        cancelInFlightTask(for: pageID)
        let currentRevision = (taskRevisions[pageID] ?? 0)

        let quad = page.cropQuadrilateral ?? .unit
        let rotation = page.rotationDegrees
        let sourceData = page.sourceData

        let task = Task {
            let result = await rectifier.rectify(jpegData: sourceData, quadrilateral: quad, rotationDegrees: rotation)
            if Task.isCancelled {
                // Cancellation only happens via `cancelInFlightTask`, which already
                // bumped the revision and removed this entry synchronously.
                return
            }
            await MainActor.run {
                // A newer edit already superseded this task and owns
                // `inFlightTasks[pageID]` now; leave its entry untouched.
                guard self.taskRevisions[pageID] == currentRevision else {
                    return
                }
                if let result, let targetIndex = self.pages.firstIndex(where: { $0.id == pageID }) {
                    self.pages[targetIndex].rectifiedData = result
                }
                // Clear in-flight state on every outcome, including a nil/failed
                // result, so `isProcessing` and Save never get stuck forever.
                self.inFlightTasks.removeValue(forKey: pageID)
            }
        }
        inFlightTasks[pageID] = task
    }

    private func autoAdjust(pageID: UUID, sessionID: UUID, via rectifier: any DocumentRectifying) {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let page = pages[index]

        let currentRevision = taskRevisions[pageID] ?? 0
        let task = Task {
            let detection = await rectifier.detect(in: page.sourceData)
            guard !Task.isCancelled else { return }
            guard let quadrilateral = ConservativeCropAdjustment.make(from: detection) else {
                finishAutoAdjustment(
                    for: pageID,
                    sessionID: sessionID,
                    revision: currentRevision,
                    quadrilateral: nil,
                    rectifiedData: nil
                )
                return
            }

            let rectified = await rectifier.rectify(
                jpegData: page.sourceData,
                quadrilateral: quadrilateral,
                rotationDegrees: page.rotationDegrees
            )
            guard !Task.isCancelled else { return }
            finishAutoAdjustment(
                for: pageID,
                sessionID: sessionID,
                revision: currentRevision,
                quadrilateral: quadrilateral,
                rectifiedData: rectified
            )
        }
        inFlightTasks[pageID] = task
    }

    private func finishAutoAdjustment(
        for pageID: UUID,
        sessionID: UUID,
        revision: Int,
        quadrilateral: CropQuadrilateral?,
        rectifiedData: Data?
    ) {
        guard taskRevisions[pageID] == revision else { return }
        let didAdjust = applyAutoAdjustment(
            for: pageID,
            quadrilateral: quadrilateral,
            rectifiedData: rectifiedData
        )
        inFlightTasks.removeValue(forKey: pageID)
        recordAutoAdjustmentResult(for: pageID, sessionID: sessionID, didAdjust: didAdjust)
    }

    private func applyAutoAdjustment(
        for pageID: UUID,
        quadrilateral: CropQuadrilateral?,
        rectifiedData: Data?
    ) -> Bool {
        guard let quadrilateral, let rectifiedData else { return false }
        guard let targetIndex = pages.firstIndex(where: { $0.id == pageID }) else { return false }
        pages[targetIndex].cropQuadrilateral = quadrilateral
        pages[targetIndex].rectifiedData = rectifiedData
        pages[targetIndex].detectionUncertain = false
        pages[targetIndex].wasAutoCropAdjusted = true
        return true
    }

    private func recordAutoAdjustmentResult(for pageID: UUID, sessionID: UUID, didAdjust: Bool) {
        guard autoAdjustmentSessionID == sessionID else { return }
        guard pendingAutoAdjustmentPageIDs.remove(pageID) != nil else { return }
        if didAdjust {
            autoAdjustedPageCount += 1
        }
        guard pendingAutoAdjustmentPageIDs.isEmpty else { return }

        autoAdjustmentSummary = AutoAdjustmentSummary(
            adjustedPageCount: autoAdjustedPageCount,
            manualReviewPageCount: uncertainPageCount
        )
        autoAdjustmentSessionID = nil
    }
}
