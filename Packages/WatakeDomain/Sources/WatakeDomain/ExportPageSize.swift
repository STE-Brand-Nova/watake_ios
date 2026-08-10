import Foundation

/// Supported PDF page sizes for bulk export.
///
/// `original` preserves the source page's exact aspect ratio.
/// `a4` and `usLetter` use fixed dimensions from ISO 216 / ANSI standards,
/// expressed in PDF points (1 point = 1/72 inch).
public enum ExportPageSize: String, Codable, Equatable, Sendable, CaseIterable {
    case original
    // ISO 216 paper size; short standard name is intentional.
    // swiftlint:disable:next identifier_name
    case a4
    case usLetter

    /// Portrait dimensions in PDF points. For `original`, callers must derive
    /// dimensions from the source image; the values here are not used.
    public var portraitDimensions: (width: Double, height: Double)? {
        switch self {
        case .original:
            nil
        case .a4:
            (width: 595.28, height: 841.89)
        case .usLetter:
            (width: 612, height: 792)
        }
    }
}
