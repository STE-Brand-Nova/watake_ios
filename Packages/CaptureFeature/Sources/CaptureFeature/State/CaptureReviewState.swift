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

        // Explicitly await all running page processing tasks before serializing pages for storage
        let tasksToAwait = Array(inFlightTasks.values)
        for task in tasksToAwait {
            _ = await task.value
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
                return
            }
            guard let result else { return }
            await MainActor.run {
                if Task.isCancelled {
                    return
                }
                let indexMatch = self.pages.firstIndex(where: { $0.id == pageID })
                guard self.taskRevisions[pageID] == currentRevision, let targetIndex = indexMatch else {
                    return
                }
                self.pages[targetIndex].rectifiedData = result
                self.inFlightTasks.removeValue(forKey: pageID)
            }
        }
        inFlightTasks[pageID] = task
    }
}
