//
//  ExportFeatureModel.swift
//  ExportFeature
//

import Foundation
import Observation
import WatakeDomain

public enum ExportUserError: Error, Equatable, Sendable {
    case noPages
    case pageUnavailable
    case renderFailed
    case storageFull
    case unknown
}

@MainActor
@Observable
public final class ExportFeatureModel: Identifiable {
    public let id = UUID()
    public enum State: Equatable {
        case idle
        case preparing
        case reviewing
        case preflightWarning(estimatedBytes: Int)
        case exporting(ExportProgress)
        case actualSizeWarning(actualBytes: Int, fileURL: URL)
        case completed(fileURL: URL, actualBytes: Int)
        case cancelled
        case failed(ExportUserError)
    }

    public private(set) var state: State = .idle
    public private(set) var draft: BulkExportDraft?

    private let documentLoader: any ExportDocumentLoading
    private let exporter: any BulkPDFExporting
    private let sizeEstimator: any ExportSizeEstimating
    private let warningPolicy: ExportWarningPolicy
    private var prepareTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var activeOutputDirectory: URL?
    private var activeOutputURL: URL?
    private var hasConfirmedPreflight = false

    public init(
        documentLoader: any ExportDocumentLoading,
        exporter: any BulkPDFExporting,
        sizeEstimator: any ExportSizeEstimating = DefaultExportSizeEstimator(),
        warningPolicy: ExportWarningPolicy = ExportWarningPolicy()
    ) {
        self.documentLoader = documentLoader
        self.exporter = exporter
        self.sizeEstimator = sizeEstimator
        self.warningPolicy = warningPolicy
    }

    public func prepareDraft(documentIDs: Set<UUID>) {
        state = .preparing
        prepareTask?.cancel()
        prepareTask = Task {
            do {
                let documents = try await documentLoader.documents(ids: documentIDs)
                if Task.isCancelled {
                    return
                }
                let defaultName = documents.first?.name ?? String(localized: "Export", comment: "Default export filename")
                let newDraft = BulkExportDraft.from(documents: documents, outputFilename: defaultName)

                if newDraft.items.isEmpty {
                    self.state = .failed(.noPages)
                } else {
                    self.draft = newDraft
                    self.state = .reviewing
                }
            } catch {
                if !Task.isCancelled {
                    self.state = .failed(.unknown)
                }
            }
        }
    }

    public func toggleInclusion(pageID: UUID) {
        draft?.toggleInclusion(pageID: pageID)
    }

    public func movePage(from source: IndexSet, to destination: Int) {
        draft?.moveItems(from: source, to: destination)
    }

    @discardableResult
    public func movePageUp(pageID: UUID) -> Int? {
        draft?.moveUp(pageID: pageID)
    }

    @discardableResult
    public func movePageDown(pageID: UUID) -> Int? {
        draft?.moveDown(pageID: pageID)
    }

    public func setPageSize(_ size: ExportPageSize) {
        draft?.pageSize = size
    }

    public func setFitMode(_ mode: ExportFitMode) {
        draft?.fitMode = mode
    }

    public func setMargin(_ margin: Double) {
        draft?.marginPoints = margin
    }

    public func setFilename(_ filename: String) {
        draft?.outputFilename = filename
    }

    public func startExport() {
        guard let draft else { return }

        do {
            try draft.validate()
        } catch {
            state = .failed(.noPages)
            return
        }

        let renderPages = draft.includedItems.map { item in
            PDFRenderPage(id: item.id, assetReference: item.assetReference)
        }
        let estimatedBytes = sizeEstimator.estimateOutputSize(pages: renderPages, pageSize: draft.pageSize, fitMode: draft.fitMode)
        if warningPolicy.shouldWarn(estimatedBytes: estimatedBytes) {
            state = .preflightWarning(estimatedBytes: estimatedBytes)
        } else {
            render()
        }
    }

    public func confirmLargeExport() {
        hasConfirmedPreflight = true
        render()
    }

    public func confirmActualSizeExport() {
        if case .actualSizeWarning(let actualBytes, let fileURL) = state {
            state = .completed(fileURL: fileURL, actualBytes: actualBytes)
        }
    }

    public func cancelWarning() {
        state = .reviewing
    }

    public func cancelExport() {
        prepareTask?.cancel()
        prepareTask = nil
        renderTask?.cancel()
        renderTask = nil
        removeActiveOutputDirectory()
        state = .cancelled
    }

    public func retry() {
        state = .reviewing
    }

    public func cleanup() {
        prepareTask?.cancel()
        prepareTask = nil
        renderTask?.cancel()
        renderTask = nil
        removeActiveOutputDirectory()
        state = .idle
        draft = nil
    }

    private func removeActiveOutputDirectory() {
        if let activeOutputDirectory {
            try? FileManager.default.removeItem(at: activeOutputDirectory)
            self.activeOutputDirectory = nil
            activeOutputURL = nil
        }
    }

    private func render() {
        guard let draft else { return }
        removeActiveOutputDirectory()

        state = .exporting(ExportProgress(completedPages: 0, totalPages: draft.includedItems.count, phase: .preparing))

        let job = makeRenderJob(for: draft)

        renderTask = Task {
            do {
                let fileURL = try await exporter.renderPDF(job: job) { progress in
                    Task { @MainActor in
                        if case .exporting = self.state {
                            self.state = .exporting(progress)
                        }
                    }
                }
                self.handleRenderSuccess(fileURL: fileURL)
            } catch {
                self.handleRenderFailure(error)
            }
        }
    }

    /// Builds the render job and records its output location so partial files
    /// can be cleaned up on cancellation or failure.
    private func makeRenderJob(for draft: BulkExportDraft) -> PDFRenderJob {
        let renderPages = draft.includedItems.map { item in
            PDFRenderPage(id: item.id, assetReference: item.assetReference)
        }

        let safeFilename = ExportFilenameSanitizer.sanitize(draft.outputFilename)
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tempURL = outputDir.appendingPathComponent("\(safeFilename).pdf")

        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        activeOutputDirectory = outputDir
        activeOutputURL = tempURL

        return PDFRenderJob(
            pages: renderPages,
            pageSize: draft.pageSize,
            fitMode: draft.fitMode,
            marginPoints: draft.marginPoints,
            outputURL: tempURL
        )
    }

    private func handleRenderSuccess(fileURL: URL) {
        if Task.isCancelled {
            removeActiveOutputDirectory()
            return
        }

        let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let actualBytes = attr?[.size] as? Int ?? 0

        if !hasConfirmedPreflight, warningPolicy.shouldWarn(estimatedBytes: actualBytes) {
            state = .actualSizeWarning(actualBytes: actualBytes, fileURL: fileURL)
        } else {
            state = .completed(fileURL: fileURL, actualBytes: actualBytes)
        }
    }

    private func handleRenderFailure(_ error: Error) {
        removeActiveOutputDirectory()
        if error is CancellationError {
            return
        }
        // An explicit ExportError.cancelled is a silent, non-failing outcome.
        if case ExportError.cancelled = error {
            return
        }
        guard !Task.isCancelled else { return }
        state = .failed(Self.userError(for: error))
    }

    private static func userError(for error: Error) -> ExportUserError {
        guard let exportError = error as? ExportError else { return .unknown }
        switch exportError {
        case .emptyDraft: return .noPages
        case .pageUnavailable: return .pageUnavailable
        case .insufficientStorage: return .storageFull
        default: return .renderFailed
        }
    }
}
