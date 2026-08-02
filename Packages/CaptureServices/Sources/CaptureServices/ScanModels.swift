import Foundation

/// Privacy-safe outcomes from the native scanner boundary. VisionKit errors
/// are intentionally not retained because their payload can contain private
/// document or camera details.
public enum NativeDocumentScannerError: Error, Equatable, Sendable {
    case cancelled
    case noPages
    case imageEncodingFailed
    case visionKitFailure
    case unavailable
}

/// Immutable encoded page returned from a scanner boundary. The native
/// VisionKit adapter always creates JPEG data on the main actor before this
/// value is handed to storage or domain work.
public struct ScannedPage: Equatable, Sendable {
    public let jpegData: Data

    public init(jpegData: Data) {
        self.jpegData = jpegData
    }
}

/// Boundary for a page-producing scanner. Test doubles implement this port;
/// UIKit and VisionKit stay outside `WatakeDomain`.
public protocol DocumentPageCapturing: Sendable {
    func capturePages() async throws -> [ScannedPage]
}

public enum DocumentScanSaveError: Error, Equatable, Sendable {
    case targetFolderMissing
    case targetFolderTrashed
    case emptyScan
}
