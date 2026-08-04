import Foundation
import Observation
import WatakeDomain

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

    /// Task revision counter per page ID to prevent stale async tasks from overwriting state.
    private var taskRevisions: [UUID: Int] = [:]

    /// Active in-flight processing tasks per page ID for explicit cancellation.
    private var inFlightTasks: [UUID: Task<Void, Never>] = [:]

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
        isSaving: Bool = false
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
    }

    /// Whether any crop/rectification/rotation processing task is currently running in-flight.
    public var isProcessing: Bool {
        !inFlightTasks.isEmpty
    }

    public var selectedPage: CaptureReviewPage? {
        guard pages.indices.contains(selectedIndex) else { return nil }
        return pages[selectedIndex]
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
        page.rectifiedData = nil // Reset rectifiedData while async crop task runs
        pages[selectedIndex] = page
        recomputeRectified(for: page.id, via: rectifier)
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
}
