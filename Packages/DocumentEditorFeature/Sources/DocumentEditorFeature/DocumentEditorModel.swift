import CryptoKit
import Foundation
import Observation
import WatakeDomain

@MainActor
@Observable
public final class DocumentEditorModel {
    public private(set) var document: StoredDocument
    public private(set) var sourceDocumentID: UUID
    public private(set) var selectedPageID: UUID
    public var selectedAnnotationID: UUID?
    public var tool: DocumentEditorTool = .select
    public private(set) var saveState: DocumentEditorSaveState = .idle
    public private(set) var folders: [Folder] = []
    public private(set) var signatures: [SavedSignature] = []
    public private(set) var pageImages: [UUID: Data] = [:]
    public private(set) var annotationImages: [UUID: Data] = [:]
    public private(set) var recoveryDraftAvailable = false
    public private(set) var errorMessage: String?
    public private(set) var toastMessage: String?
    public private(set) var toastRevision = 0
    public private(set) var highlightColorHex = "#FBBF24"
    public private(set) var highlightOpacity = 0.42
    public private(set) var highlightWidth = 0.025
    public private(set) var autoStraightenHighlights = true
    public private(set) var pendingImagePlacement: PendingImagePlacement?
    public private(set) var isCommittingImagePlacement = false

    private let store: any DocumentEditingStore
    private let now: @Sendable () -> Date
    private let makeUUID: @Sendable () -> UUID
    private let pageThumbnailLoader: @MainActor @Sendable (DocumentPage) async throws -> Data
    private let onPersisted: @MainActor @Sendable (StoredDocument, Bool) -> Void
    private var baseline: StoredDocument
    private var histories: [UUID: PageHistory] = [:]
    private var stagedAssets: [AssetReference] = []
    private var continuousBaseline: [PageAnnotation]?
    private var recoveryTask: Task<Void, Never>?
    private var textHistoryTask: Task<Void, Never>?
    private var textHistoryBaseline: [PageAnnotation]?
    private var textHistoryPageID: UUID?
    private var pageThumbnailCache: [UUID: PageThumbnailCacheEntry] = [:]

    public init(
        document: StoredDocument,
        store: any DocumentEditingStore,
        now: @escaping @Sendable () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init,
        pageThumbnailLoader: (@MainActor @Sendable (DocumentPage) async throws -> Data)? = nil,
        onPersisted: @escaping @MainActor @Sendable (StoredDocument, Bool) -> Void = { _, _ in }
    ) {
        self.document = document
        baseline = document
        sourceDocumentID = document.id
        selectedPageID = document.pages.min(by: { $0.index < $1.index })?.id ?? UUID()
        self.store = store
        self.now = now
        self.makeUUID = makeUUID
        self.pageThumbnailLoader = pageThumbnailLoader ?? { page in
            try await store.readAsset(page.rectified ?? page.source)
        }
        self.onPersisted = onPersisted
    }
}

extension DocumentEditorModel {
    public var pages: [DocumentPage] {
        document.pages.sorted { $0.index < $1.index }
    }

    public var selectedPage: DocumentPage? {
        document.pages.first { $0.id == selectedPageID }
    }

    public var selectedAnnotation: PageAnnotation? {
        guard let selectedAnnotationID else { return nil }
        return selectedPage?.annotations.first { $0.id == selectedAnnotationID }
    }

    public var isDirty: Bool {
        document.pages != baseline.pages || document.name != baseline.name || document.folderId != baseline.folderId
    }

    public var canUndo: Bool {
        !(histories[selectedPageID]?.undo.isEmpty ?? true)
    }

    public var canRedo: Bool {
        !(histories[selectedPageID]?.redo.isEmpty ?? true)
    }

    public func load() async {
        do {
            async let loadedFolders = store.folders()
            async let loadedSignatures = store.savedSignatures()
            async let recovery = store.recoveryDraft(documentID: sourceDocumentID)
            let folderValues = try await loadedFolders
            folders = folderValues.filter { $0.deletedAt == nil }
            signatures = try await loadedSignatures
            let recoveryValue = try await recovery
            recoveryDraftAvailable = recoveryValue != nil
            await loadImagesForSelectedPage()
        } catch {
            errorMessage = "Some editor resources could not be loaded."
        }
    }

    public func selectPage(_ pageID: UUID) {
        finishTextHistory()
        guard document.pages.contains(where: { $0.id == pageID }) else { return }
        pendingImagePlacement = nil
        selectedPageID = pageID
        selectedAnnotationID = nil
        tool = .select
        continuousBaseline = nil
        retainImageCaches(for: pageID)
        Task { await loadImagesForSelectedPage() }
    }

    public func loadPageImage(for pageID: UUID) async {
        guard let page = document.pages.first(where: { $0.id == pageID }) else { return }
        if pageImages[pageID] == nil {
            pageImages[pageID] = try? await store.readAsset(page.rectified ?? page.source)
        }
        for reference in page.annotations.compactMap(\.image) where annotationImages[reference.id] == nil {
            annotationImages[reference.id] = try? await store.readAsset(reference)
        }
    }

    public func pageThumbnailData(for page: DocumentPage) async -> Data? {
        if let cached = pageThumbnailCache[page.id], cached.page == page {
            return cached.data
        }
        guard let data = try? await pageThumbnailLoader(page), !Task.isCancelled else { return nil }
        guard document.pages.first(where: { $0.id == page.id }) == page else { return nil }
        pageThumbnailCache[page.id] = PageThumbnailCacheEntry(page: page, data: data)
        return data
    }

    public func selectAnnotation(_ annotationID: UUID?) {
        selectedAnnotationID = annotationID
        guard let annotationID,
              let annotation = selectedPage?.annotations.first(where: { $0.id == annotationID }) else { return }
        tool = annotation.kind == .text ? .text : .select
    }

    public func activateTool(_ tool: DocumentEditorTool) {
        if tool != .image {
            pendingImagePlacement = nil
        }
        selectedAnnotationID = nil
        self.tool = tool
    }

    public func setHighlightDrawingColor(_ colorHex: String) {
        guard DocumentEditorPalette.highlightColors.contains(colorHex) else { return }
        highlightColorHex = colorHex
    }

    public func setHighlightDrawingStyle(width: Double, colorHex: String, opacity: Double) {
        highlightWidth = DocumentEditorPalette.clampedHighlightWidth(width)
        if DocumentEditorPalette.highlightColors.contains(colorHex) {
            highlightColorHex = colorHex
        }
        highlightOpacity = min(max(opacity, 0), 1)
    }

    public func setHighlightAutoStraighten(_ enabled: Bool) {
        autoStraightenHighlights = enabled
    }
}

extension DocumentEditorModel {
    public func addText(_ value: String = "Text") {
        let limitedValue = String(value.prefix(AnnotationText.maximumLength))
        let text = limitedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let annotation = PageAnnotation(
            id: makeUUID(),
            kind: .text,
            transform: .init(centerX: 0.5, centerY: 0.3, width: 0.58, height: 0.12),
            zIndex: nextZIndex,
            text: AnnotationText(text: limitedValue)
        )
        append(annotation)
    }

    public func addSignature(strokes: [InkStroke]) {
        guard !strokes.isEmpty else { return }
        let annotation = PageAnnotation(
            id: makeUUID(),
            kind: .signature,
            transform: .init(centerX: 0.5, centerY: 0.72, width: 0.42, height: 0.16),
            zIndex: nextZIndex,
            strokes: strokes
        )
        append(annotation)
    }

    public func applySignature(_ signature: SavedSignature) {
        addSignature(strokes: signature.strokes)
    }

    public func saveSignature(name: String, strokes: [InkStroke]) async -> Bool {
        let timestamp = now()
        let signature = SavedSignature(id: makeUUID(), name: name, strokes: strokes, createdAt: timestamp, updatedAt: timestamp)
        do {
            try await store.saveSignature(signature)
            signatures = try await store.savedSignatures()
            return true
        } catch {
            errorMessage = "Signature could not be saved."
            return false
        }
    }

    public func addHighlight(points: [InkPoint], pageSize: CGSize, straightened: Bool) {
        guard let prepared = DocumentHighlightInteraction.prepare(
            points: points,
            pageSize: pageSize,
            width: highlightWidth,
            colorHex: highlightColorHex,
            opacity: highlightOpacity
        ) else { return }
        let annotation = PageAnnotation(
            id: makeUUID(),
            kind: .highlight,
            transform: prepared.transform,
            zIndex: nextZIndex,
            strokes: [prepared.stroke],
            isStraightened: straightened
        )
        append(annotation, selectsAnnotation: false)
        tool = .highlight
    }

    @discardableResult
    public func prepareImagePlacement(
        data: Data,
        mediaType: String,
        fileExtension: String,
        aspectRatio: Double
    ) -> Bool {
        guard !data.isEmpty, aspectRatio.isFinite, aspectRatio > 0 else { return false }
        pendingImagePlacement = PendingImagePlacement(
            id: makeUUID(),
            data: data,
            mediaType: mediaType,
            fileExtension: fileExtension,
            aspectRatio: min(max(aspectRatio, 0.02), 50)
        )
        selectedAnnotationID = nil
        tool = .image
        return true
    }

    public func cancelImagePlacement() {
        pendingImagePlacement = nil
        isCommittingImagePlacement = false
        if tool == .image {
            tool = .select
        }
    }

    public func placePendingImage(transform: AnnotationTransform) async -> Bool {
        guard let pendingImagePlacement, !isCommittingImagePlacement else { return false }
        guard (try? transform.validate()) != nil else { return false }
        let placementPageID = selectedPageID
        isCommittingImagePlacement = true
        defer { isCommittingImagePlacement = false }
        guard let reference = await stageImage(
            data: pendingImagePlacement.data,
            mediaType: pendingImagePlacement.mediaType,
            fileExtension: pendingImagePlacement.fileExtension
        ) else { return false }
        guard self.pendingImagePlacement == pendingImagePlacement, selectedPageID == placementPageID else {
            await discardStagedReference(reference)
            return false
        }
        self.pendingImagePlacement = nil
        append(PageAnnotation(
            id: makeUUID(),
            kind: .image,
            transform: transform,
            zIndex: nextZIndex,
            image: reference
        ))
        return true
    }

    public func importImage(data: Data, mediaType: String, fileExtension: String) async -> Bool {
        guard let reference = await stageImage(data: data, mediaType: mediaType, fileExtension: fileExtension) else {
            return false
        }
        append(PageAnnotation(
            id: makeUUID(),
            kind: .image,
            transform: .init(centerX: 0.5, centerY: 0.5, width: 0.5, height: 0.3),
            zIndex: nextZIndex,
            image: reference
        ))
        return true
    }

    public func replaceSelectedImage(data: Data, mediaType: String, fileExtension: String) async -> Bool {
        guard let selectedAnnotationID,
              selectedAnnotation?.kind == .image else {
            return false
        }
        let pageID = selectedPageID
        guard let reference = await stageImage(data: data, mediaType: mediaType, fileExtension: fileExtension) else {
            return false
        }
        guard selectedPageID == pageID,
              self.selectedAnnotationID == selectedAnnotationID,
              let page = selectedPage,
              let index = page.annotations.firstIndex(where: { $0.id == selectedAnnotationID && $0.kind == .image }) else {
            await discardStagedReference(reference)
            return false
        }
        var annotations = page.annotations
        let current = annotations[index]
        annotations[index] = PageAnnotation(
            id: current.id, kind: current.kind, transform: current.transform, opacity: current.opacity,
            zIndex: current.zIndex, text: current.text, strokes: current.strokes, image: reference,
            isStraightened: current.isStraightened,
            isFlippedHorizontally: current.isFlippedHorizontally,
            isFlippedVertically: current.isFlippedVertically
        )
        setAnnotations(annotations, recording: page.annotations)
        return true
    }

    public func rotateSelectedImage(by degrees: Double) {
        guard selectedAnnotation?.kind == .image else { return }
        transformSelected(rotationDelta: degrees)
    }

    public func resetSelectedImageRotation() {
        guard let annotation = selectedAnnotation, annotation.kind == .image else { return }
        transformSelected(rotationDelta: -annotation.transform.rotation)
    }

    public func flipSelectedImageHorizontally() {
        updateSelectedImageFlips(horizontal: true)
    }

    public func flipSelectedImageVertically() {
        updateSelectedImageFlips(horizontal: false)
    }

    private func stageImage(data: Data, mediaType: String, fileExtension: String) async -> AssetReference? {
        guard !data.isEmpty else { return nil }
        let assetID = makeUUID()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let safeExtension = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        let relativePath = "annotations/\(sourceDocumentID.uuidString.lowercased())/" +
            "\(assetID.uuidString.lowercased()).\(safeExtension.isEmpty ? "img" : safeExtension)"
        let reference = AssetReference(
            id: assetID,
            relativePath: relativePath,
            sha256Hex: digest,
            byteSize: data.count,
            mediaType: mediaType
        )
        do {
            try await store.stageAnnotationAsset(data, reference: reference)
            stagedAssets.append(reference)
            annotationImages[reference.id] = data
            return reference
        } catch {
            errorMessage = "Image could not be added."
            return nil
        }
    }

    private func updateSelectedImageFlips(horizontal: Bool) {
        guard selectedAnnotation?.kind == .image else { return }
        replaceSelected { current in
            PageAnnotation(
                id: current.id, kind: current.kind, transform: current.transform, opacity: current.opacity,
                zIndex: current.zIndex, text: current.text, strokes: current.strokes, image: current.image,
                isStraightened: current.isStraightened,
                isFlippedHorizontally: horizontal ? !current.isFlippedHorizontally : current.isFlippedHorizontally,
                isFlippedVertically: horizontal ? current.isFlippedVertically : !current.isFlippedVertically
            )
        }
    }

    private func discardStagedReference(_ reference: AssetReference) async {
        stagedAssets.removeAll { $0.id == reference.id }
        annotationImages.removeValue(forKey: reference.id)
        await store.discardAnnotationAssets([reference])
    }

    public func updateSelectedText(_ value: AnnotationText) {
        guard (try? value.validate()) != nil else { return }
        if textHistoryBaseline == nil {
            textHistoryBaseline = selectedPage?.annotations
            textHistoryPageID = selectedPageID
        }
        replaceSelected(recordHistory: false) { current in
            PageAnnotation(
                id: current.id, kind: current.kind, transform: current.transform, opacity: current.opacity,
                zIndex: current.zIndex, text: value, strokes: current.strokes, image: current.image,
                isStraightened: current.isStraightened,
                isFlippedHorizontally: current.isFlippedHorizontally,
                isFlippedVertically: current.isFlippedVertically
            )
        }
        textHistoryTask?.cancel()
        textHistoryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.finishTextHistory()
            } catch is CancellationError {
                // More typing extends current coalesced command.
            } catch {
                // History remains best-effort; document draft is still safe.
            }
        }
    }

    public func updateSelectedOpacity(_ value: Double) {
        replaceSelected(recordHistory: continuousBaseline == nil) { current in
            PageAnnotation(
                id: current.id, kind: current.kind, transform: current.transform, opacity: min(max(value, 0), 1),
                zIndex: current.zIndex, text: current.text, strokes: current.strokes, image: current.image,
                isStraightened: current.isStraightened,
                isFlippedHorizontally: current.isFlippedHorizontally,
                isFlippedVertically: current.isFlippedVertically
            )
        }
    }

    public func updateSelectedStrokeStyle(width: Double, colorHex: String, opacity: Double) {
        let clampedWidth = selectedAnnotation?.kind == .highlight
            ? DocumentEditorPalette.clampedHighlightWidth(width)
            : min(max(width, 0.002), 0.08)
        let clampedOpacity = min(max(opacity, 0), 1)
        replaceSelected(recordHistory: continuousBaseline == nil) { current in
            let strokes = current.strokes.map {
                InkStroke(points: $0.points, width: clampedWidth, colorHex: colorHex, opacity: clampedOpacity)
            }
            return PageAnnotation(
                id: current.id, kind: current.kind, transform: current.transform, opacity: current.opacity,
                zIndex: current.zIndex, text: current.text, strokes: strokes, image: current.image,
                isStraightened: current.isStraightened,
                isFlippedHorizontally: current.isFlippedHorizontally,
                isFlippedVertically: current.isFlippedVertically
            )
        }
    }

    public func beginContinuousEdit() {
        if continuousBaseline == nil {
            continuousBaseline = selectedPage?.annotations
        }
    }

    public func transformSelected(
        centerX: Double? = nil,
        centerY: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        scale: Double = 1,
        rotationDelta: Double = 0
    ) {
        guard let selectedAnnotation else { return }
        let old = selectedAnnotation.transform
        let snappedX = centerX.map { selectedAnnotation.kind == .image ? $0 : snap($0) } ?? old.centerX
        let snappedY = centerY.map { selectedAnnotation.kind == .image ? $0 : snap($0) } ?? old.centerY
        let transformed = AnnotationTransform(
            centerX: min(max(snappedX, 0), 1),
            centerY: min(max(snappedY, 0), 1),
            width: min(max(width ?? old.width * scale, 0.01), 1),
            height: min(max(height ?? old.height * scale, 0.01), 1),
            rotation: normalizedRotation(old.rotation + rotationDelta)
        )
        replaceSelected(recordHistory: continuousBaseline == nil) { current in
            PageAnnotation(
                id: current.id, kind: current.kind, transform: transformed, opacity: current.opacity,
                zIndex: current.zIndex, text: current.text, strokes: current.strokes, image: current.image,
                isStraightened: current.isStraightened,
                isFlippedHorizontally: current.isFlippedHorizontally,
                isFlippedVertically: current.isFlippedVertically
            )
        }
    }

    public func endContinuousEdit() {
        guard let before = continuousBaseline else { return }
        continuousBaseline = nil
        guard let current = selectedPage?.annotations else { return }
        guard before != current else { return }
        histories[selectedPageID, default: PageHistory()].record(before)
        changed()
    }
}

extension DocumentEditorModel {
    public func deleteSelected() {
        guard let selectedAnnotationID, let page = selectedPage,
              let annotation = page.annotations.first(where: { $0.id == selectedAnnotationID }) else { return }
        setAnnotations(page.annotations.filter { $0.id != selectedAnnotationID }, recording: page.annotations)
        self.selectedAnnotationID = nil
        if annotation.kind == .text || annotation.kind == .image {
            toastRevision += 1
            toastMessage = annotation.kind == .text ? "Text deleted" : "Image deleted"
        }
    }

    public func duplicateSelected(to pageIDs: Set<UUID>? = nil) {
        guard let selectedAnnotation else { return }
        let targets = pageIDs ?? [selectedPageID]
        for pageID in targets {
            guard let page = document.pages.first(where: { $0.id == pageID }) else { continue }
            let duplicateTransform = selectedAnnotation.kind == .image && pageID == selectedPageID
                ? offsetImageDuplicate(selectedAnnotation.transform)
                : selectedAnnotation.transform
            let duplicate = PageAnnotation(
                id: makeUUID(), kind: selectedAnnotation.kind, transform: duplicateTransform,
                opacity: selectedAnnotation.opacity, zIndex: page.annotations.count,
                text: selectedAnnotation.text, strokes: selectedAnnotation.strokes, image: selectedAnnotation.image,
                isStraightened: selectedAnnotation.isStraightened,
                isFlippedHorizontally: selectedAnnotation.isFlippedHorizontally,
                isFlippedVertically: selectedAnnotation.isFlippedVertically
            )
            setAnnotations(page.annotations + [duplicate], for: pageID, recording: page.annotations)
            if pageID == selectedPageID {
                selectedAnnotationID = duplicate.id
            }
        }
    }

    public func bringForward() {
        moveSelectedLayer(by: 1)
    }

    public func sendBackward() {
        moveSelectedLayer(by: -1)
    }

    public func undo() {
        finishTextHistory()
        guard let page = selectedPage, var history = histories[selectedPageID],
              let annotations = history.undo(current: page.annotations) else { return }
        histories[selectedPageID] = history
        setAnnotations(annotations, recording: nil)
        selectedAnnotationID = nil
        changed()
    }

    public func redo() {
        finishTextHistory()
        guard let page = selectedPage, var history = histories[selectedPageID],
              let annotations = history.redo(current: page.annotations) else { return }
        histories[selectedPageID] = history
        setAnnotations(annotations, recording: nil)
        selectedAnnotationID = nil
        changed()
    }

    public func revertAllEdits() {
        for page in document.pages where !page.annotations.isEmpty {
            setAnnotations([], for: page.id, recording: page.annotations)
        }
        selectedAnnotationID = nil
    }

    public func save() async -> Bool {
        finishTextHistory()
        recoveryTask?.cancel()
        recoveryTask = nil
        saveState = .saving
        let saved = replacingDocumentMetadata(document, updatedAt: now())
        do {
            try await store.saveEditedDocument(saved)
            try? await store.deleteRecoveryDraft(documentID: sourceDocumentID)
            await store.discardAnnotationAssets(stagedAssets)
            document = saved
            baseline = saved
            histories.removeAll()
            stagedAssets.removeAll()
            saveState = .idle
            onPersisted(saved, false)
            return true
        } catch {
            saveState = .failed
            errorMessage = "Changes could not be saved. Your draft remains available."
            scheduleRecovery()
            return false
        }
    }

    public func saveCopy(name: String, folderID: UUID) async -> Bool {
        finishTextHistory()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let oldSelectedIndex = selectedPage?.index else { return false }
        recoveryTask?.cancel()
        recoveryTask = nil
        saveState = .saving
        do {
            let existing = try await store.documents(in: folderID)
            let copy = makeCopy(name: trimmedName, folderID: folderID, orderIndex: (existing.map(\.orderIndex).max() ?? -1) + 1)
            try await store.saveDocumentCopy(copy, sourceDocumentID: sourceDocumentID)
            try? await store.deleteRecoveryDraft(documentID: sourceDocumentID)
            await store.discardAnnotationAssets(stagedAssets)
            document = copy
            baseline = copy
            sourceDocumentID = copy.id
            selectedPageID = copy.pages.first(where: { $0.index == oldSelectedIndex })?.id ?? copy.pages[0].id
            selectedAnnotationID = nil
            histories.removeAll()
            stagedAssets.removeAll()
            saveState = .savedCopy
            onPersisted(copy, true)
            retainImageCaches(for: selectedPageID)
            await loadImagesForSelectedPage()
            return true
        } catch {
            saveState = .failed
            errorMessage = "Copy could not be saved. Your draft remains available."
            scheduleRecovery()
            return false
        }
    }

    public func resumeRecoveryDraft() async {
        do {
            guard let recovery = try await store.recoveryDraft(documentID: sourceDocumentID) else {
                recoveryDraftAvailable = false
                return
            }
            document = recovery.document
            selectedPageID = recovery.selectedPageID
            stagedAssets = recovery.stagedAssets
            recoveryDraftAvailable = false
            retainImageCaches(for: selectedPageID)
            await loadImagesForSelectedPage()
        } catch {
            errorMessage = "Draft could not be restored."
        }
    }

    public func discardRecoveryDraft() async {
        let originalID = sourceDocumentID
        let references = await (try? store.recoveryDraft(documentID: originalID))?.stagedAssets ?? []
        try? await store.deleteRecoveryDraft(documentID: originalID)
        await store.discardAnnotationAssets(references)
        recoveryDraftAvailable = false
    }

    public func discardCurrentDraft() async {
        recoveryTask?.cancel()
        try? await store.deleteRecoveryDraft(documentID: sourceDocumentID)
        await store.discardAnnotationAssets(stagedAssets)
        stagedAssets.removeAll()
    }

    public func clearMessage() {
        errorMessage = nil
    }

    public func clearToast(revision: Int) {
        guard toastRevision == revision else { return }
        toastMessage = nil
    }
}

extension DocumentEditorModel {
    private var nextZIndex: Int {
        (selectedPage?.annotations.map(\.zIndex).max() ?? -1) + 1
    }

    private func append(_ annotation: PageAnnotation, selectsAnnotation: Bool = true) {
        guard let page = selectedPage else { return }
        guard (try? annotation.validate()) != nil else {
            errorMessage = "This \(annotation.kind.rawValue) could not be added."
            return
        }
        setAnnotations(page.annotations + [annotation], recording: page.annotations)
        if selectsAnnotation {
            selectedAnnotationID = annotation.id
            tool = annotation.kind == .text ? .text : .select
        } else {
            selectedAnnotationID = nil
        }
    }

    private func replaceSelected(recordHistory: Bool = true, _ transform: (PageAnnotation) -> PageAnnotation) {
        guard let page = selectedPage, let selectedAnnotationID,
              let index = page.annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else { return }
        var annotations = page.annotations
        annotations[index] = transform(annotations[index])
        setAnnotations(annotations, recording: recordHistory ? page.annotations : nil)
    }

    private func moveSelectedLayer(by offset: Int) {
        guard let page = selectedPage, let selectedAnnotationID,
              let index = page.annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else { return }
        let target = min(max(index + offset, 0), page.annotations.count - 1)
        guard target != index else { return }
        var ordered = page.annotations.sorted { $0.zIndex < $1.zIndex }
        guard let orderedIndex = ordered.firstIndex(where: { $0.id == selectedAnnotationID }) else { return }
        let item = ordered.remove(at: orderedIndex)
        ordered.insert(item, at: min(max(orderedIndex + offset, 0), ordered.count))
        setAnnotations(reindexed(ordered), recording: page.annotations)
    }

    private func setAnnotations(_ annotations: [PageAnnotation], for pageID: UUID? = nil, recording before: [PageAnnotation]?) {
        let pageID = pageID ?? selectedPageID
        guard let index = document.pages.firstIndex(where: { $0.id == pageID }) else { return }
        if let before {
            histories[pageID, default: PageHistory()].record(before)
        }
        var pages = document.pages
        let page = pages[index]
        pages[index] = DocumentPage(
            id: page.id, index: page.index, originalIndex: page.originalIndex, source: page.source,
            rectified: page.rectified, ocrText: page.ocrText, ocrBlocks: page.ocrBlocks,
            annotations: reindexed(annotations)
        )
        document = replacingPages(document, pages: pages)
        changed()
    }

    private func reindexed(_ annotations: [PageAnnotation]) -> [PageAnnotation] {
        annotations.enumerated().map { index, item in
            PageAnnotation(
                id: item.id, kind: item.kind, transform: item.transform, opacity: item.opacity, zIndex: index,
                text: item.text, strokes: item.strokes, image: item.image, isStraightened: item.isStraightened,
                isFlippedHorizontally: item.isFlippedHorizontally,
                isFlippedVertically: item.isFlippedVertically
            )
        }
    }

    private func changed() {
        scheduleRecovery()
    }

    private func finishTextHistory() {
        textHistoryTask?.cancel()
        textHistoryTask = nil
        guard let pageID = textHistoryPageID, let before = textHistoryBaseline,
              let current = document.pages.first(where: { $0.id == pageID })?.annotations else {
            textHistoryBaseline = nil
            textHistoryPageID = nil
            return
        }
        if before != current {
            histories[pageID, default: PageHistory()].record(before)
        }
        textHistoryBaseline = nil
        textHistoryPageID = nil
    }

    private func scheduleRecovery() {
        recoveryTask?.cancel()
        guard isDirty, let selectedPage else { return }
        let recovery = DocumentEditRecoveryDraft(
            document: document, sourceDocumentID: sourceDocumentID, selectedPageID: selectedPage.id,
            stagedAssets: stagedAssets, savedAt: now()
        )
        do {
            try recovery.validate()
        } catch {
            errorMessage = "This edit is invalid and was not added to the recovery draft."
            return
        }
        recoveryTask = Task { [weak self, store] in
            do {
                try await Task.sleep(for: .milliseconds(600))
                try Task.checkCancellation()
                try await store.saveRecoveryDraft(recovery)
            } catch is CancellationError {
                // Superseded edits intentionally replace older recovery writes.
            } catch {
                self?.errorMessage = "Recovery draft could not be updated. Keep the editor open and try saving again."
            }
        }
    }

    private func loadImagesForSelectedPage() async {
        await loadPageImage(for: selectedPageID)
    }

    private func retainImageCaches(for pageID: UUID) {
        let pageIDs = Set(document.pages.map(\.id))
        pageThumbnailCache = pageThumbnailCache.filter { pageIDs.contains($0.key) }
        pageImages = pageImages.filter { $0.key == pageID }
        let annotationIDs = Set(
            document.pages.first(where: { $0.id == pageID })?.annotations.compactMap(\.image?.id) ?? []
        )
        annotationImages = annotationImages.filter { annotationIDs.contains($0.key) }
    }

    private func makeCopy(name: String, folderID: UUID, orderIndex: Int) -> StoredDocument {
        let timestamp = now()
        let pages = document.pages.map { page in
            DocumentPage(
                id: makeUUID(), index: page.index, originalIndex: page.originalIndex, source: page.source,
                rectified: page.rectified, ocrText: page.ocrText, ocrBlocks: page.ocrBlocks,
                annotations: page.annotations.map { item in
                    PageAnnotation(
                        id: makeUUID(), kind: item.kind, transform: item.transform, opacity: item.opacity,
                        zIndex: item.zIndex, text: item.text, strokes: item.strokes, image: item.image,
                        isStraightened: item.isStraightened,
                        isFlippedHorizontally: item.isFlippedHorizontally,
                        isFlippedVertically: item.isFlippedVertically
                    )
                }
            )
        }
        return StoredDocument(
            id: makeUUID(), folderId: folderID, name: name, createdAt: timestamp, updatedAt: timestamp,
            orderIndex: orderIndex, pages: pages, tagIds: document.tagIds,
            watermarkPresetId: document.watermarkPresetId
        )
    }

    private func replacingPages(_ document: StoredDocument, pages: [DocumentPage]) -> StoredDocument {
        StoredDocument(
            id: document.id, folderId: document.folderId, name: document.name, createdAt: document.createdAt,
            updatedAt: document.updatedAt, orderIndex: document.orderIndex, pages: pages,
            deletedAt: document.deletedAt, tagIds: document.tagIds, watermarkPresetId: document.watermarkPresetId
        )
    }

    private func replacingDocumentMetadata(_ document: StoredDocument, updatedAt: Date) -> StoredDocument {
        StoredDocument(
            id: document.id, folderId: document.folderId, name: document.name, createdAt: document.createdAt,
            updatedAt: updatedAt, orderIndex: document.orderIndex, pages: document.pages,
            deletedAt: document.deletedAt, tagIds: document.tagIds, watermarkPresetId: document.watermarkPresetId
        )
    }

    private func snap(_ value: Double) -> Double {
        abs(value - 0.5) <= 0.015 ? 0.5 : value
    }

    private func offsetImageDuplicate(_ transform: AnnotationTransform) -> AnnotationTransform {
        let offset = 0.03
        let centerX = transform.centerX <= 1 - offset ? transform.centerX + offset : transform.centerX - offset
        let centerY = transform.centerY <= 1 - offset ? transform.centerY + offset : transform.centerY - offset
        return AnnotationTransform(
            centerX: min(max(centerX, 0), 1), centerY: min(max(centerY, 0), 1),
            width: transform.width, height: transform.height, rotation: transform.rotation
        )
    }

    private func normalizedRotation(_ value: Double) -> Double {
        var output = value.truncatingRemainder(dividingBy: 360)
        if output > 180 {
            output -= 360
        }
        if output < -180 {
            output += 360
        }
        return output
    }
}
