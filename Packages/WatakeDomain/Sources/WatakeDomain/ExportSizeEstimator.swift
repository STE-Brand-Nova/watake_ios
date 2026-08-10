import Foundation

/// Approximate output size estimator for export preflight warnings.
///
/// Implementations return a best-effort estimate based on available asset
/// metadata and rendering settings without decoding every full-resolution
/// image. The estimate is intentionally conservative (overestimates).
public protocol ExportSizeEstimating: Sendable {
    /// Returns an estimated output file size in bytes.
    func estimateOutputSize(
        pages: [PDFRenderPage],
        pageSize: ExportPageSize,
        fitMode: ExportFitMode
    ) -> Int
}

/// Default estimator that sums source asset byte sizes with a compression
/// factor. JPEG sources typically compress well in PDF; raw raster does not.
public struct DefaultExportSizeEstimator: ExportSizeEstimating, Sendable {
    /// Per-page overhead for PDF structure (catalog, page tree, xref, etc.).
    private let perPageOverheadBytes: Int
    /// Multiplier applied to source byte sizes to approximate PDF output size.
    /// PDF image streams are often larger than JPEG due to re-encoding.
    private let compressionFactor: Double

    public init(perPageOverheadBytes: Int = 2048, compressionFactor: Double = 1.1) {
        self.perPageOverheadBytes = perPageOverheadBytes
        self.compressionFactor = compressionFactor
    }

    public func estimateOutputSize(
        pages: [PDFRenderPage],
        pageSize: ExportPageSize,
        fitMode: ExportFitMode
    ) -> Int {
        let assetBytes = pages.reduce(0) { $0 + $1.assetReference.byteSize }
        let overhead = pages.count * perPageOverheadBytes
        return Int(Double(assetBytes) * compressionFactor) + overhead
    }
}

/// Injectable warning policy for large exports.
public struct ExportWarningPolicy: Equatable, Sendable {
    /// Threshold in bytes above which a warning is shown.
    public let thresholdBytes: Int

    public init(thresholdBytes: Int = 50 * 1024 * 1024) {
        self.thresholdBytes = thresholdBytes
    }

    /// Whether the estimated size exceeds the warning threshold.
    public func shouldWarn(estimatedBytes: Int) -> Bool {
        estimatedBytes >= thresholdBytes
    }
}
