import Foundation

/// How a source image is placed inside the content rectangle.
///
/// - `fit`: Aspect-fit the full page inside the content rect. Blank space is
///   expected and uses the export background color.
/// - `fill`: Aspect-fill and center-crop to the content rect. Drawing is
///   clipped to the content rect; nothing is drawn into configured margins.
public enum ExportFitMode: String, Codable, Equatable, Sendable, CaseIterable {
    case fit
    case fill
}
