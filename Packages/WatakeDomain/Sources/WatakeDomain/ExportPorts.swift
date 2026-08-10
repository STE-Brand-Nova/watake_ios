import Foundation

/// Renders ordered pages into a single PDF file at a temporary URL.
/// Reports monotonic progress. Supports cooperative cancellation.
///
/// Implementations own Core Graphics, ImageIO, and PDFKit; callers exchange
/// only domain value types. Never mutates, replaces, or deletes source assets.
public protocol BulkPDFExporting: Sendable {
    /// Renders the pages described by `job` into a PDF at `job.outputURL`.
    ///
    /// - Parameters:
    ///   - job: The immutable render specification.
    ///   - progress: Called after each page completes with monotonic counts.
    /// - Returns: The URL of the completed, verified PDF file.
    /// - Throws: `ExportError` on failure; the partial file is removed.
    func renderPDF(
        job: PDFRenderJob,
        progress: @Sendable (ExportProgress) -> Void
    ) async throws -> URL
}

/// Immutable specification for one PDF render operation.
public struct PDFRenderJob: Equatable, Sendable {
    /// Ordered pages to render (included-only, in draft order).
    public let pages: [PDFRenderPage]
    /// Target page size.
    public let pageSize: ExportPageSize
    /// Fit or fill mode.
    public let fitMode: ExportFitMode
    /// Margin in PDF points (non-negative).
    public let marginPoints: Double
    /// Destination file URL (in the temporary directory).
    public let outputURL: URL

    public init(
        pages: [PDFRenderPage],
        pageSize: ExportPageSize,
        fitMode: ExportFitMode,
        marginPoints: Double,
        outputURL: URL
    ) {
        self.pages = pages
        self.pageSize = pageSize
        self.fitMode = fitMode
        self.marginPoints = marginPoints
        self.outputURL = outputURL
    }
}

/// One page to render, carrying the asset reference for the renderer to load.
public struct PDFRenderPage: Equatable, Sendable {
    /// The `DocumentPage.id`.
    public let id: UUID
    /// The best-available asset reference for this page.
    public let assetReference: AssetReference

    public init(id: UUID, assetReference: AssetReference) {
        self.id = id
        self.assetReference = assetReference
    }
}

/// Monotonic export progress report.
public struct ExportProgress: Equatable, Sendable {
    /// Number of pages fully rendered so far.
    public let completedPages: Int
    /// Total number of pages in the job.
    public let totalPages: Int
    /// Current phase of the export.
    public let phase: ExportPhase

    public init(completedPages: Int, totalPages: Int, phase: ExportPhase) {
        self.completedPages = completedPages
        self.totalPages = totalPages
        self.phase = phase
    }

    /// Completion fraction in [0, 1].
    public var fraction: Double {
        guard totalPages > 0 else { return 0 }
        return Double(completedPages) / Double(totalPages)
    }
}

/// Named phases for user-visible progress display.
public enum ExportPhase: Equatable, Sendable {
    case preparing
    case rendering(pageIndex: Int)
    case finishing
}

/// Narrow read-only port for loading documents and their pages for export.
///
/// Feature code never depends on the full `DocumentRepository` or
/// `DocumentAssetStore` surface. Implementations resolve document IDs to
/// `StoredDocument` values on the main actor and hand off immutable data.
public protocol ExportDocumentLoading: Sendable {
    /// Loads documents by their IDs. Returns only documents that exist and
    /// are not in trash. Missing IDs are silently omitted.
    func documents(ids: Set<UUID>) async throws -> [StoredDocument]
}

/// Sanitizes a user-friendly filename for PDF export output.
///
/// Removes path separators, control characters, and limits length while
/// retaining Unicode display characters. Never logs the original filename.
public enum ExportFilenameSanitizer {
    /// Maximum filename length (excluding extension).
    public static let maxLength = 100

    /// Returns a sanitized filename suitable for the PDF output file.
    /// Falls back to a default name if the input is empty after sanitization.
    public static func sanitize(_ filename: String) -> String {
        var sanitized = filename
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove control characters
        sanitized = sanitized.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 0x20 }
            .map { String($0) }
            .joined()

        if sanitized.isEmpty {
            sanitized = "Watake Export"
        }

        if sanitized.count > maxLength {
            sanitized = String(sanitized.prefix(maxLength))
        }

        return sanitized
    }
}
