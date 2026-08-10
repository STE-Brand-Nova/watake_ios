import Foundation

/// Privacy-safe, typed export failures. Never carry document names, page
/// content, file paths, or raw framework error payloads.
public enum ExportError: Error, Equatable, Sendable {
    /// The draft contains zero included pages.
    case emptyDraft
    /// A referenced page or asset is no longer available.
    case pageUnavailable(pageID: UUID)
    /// Asset data could not be read from the store.
    case assetUnreadable(pageID: UUID)
    /// Asset data could not be decoded as an image.
    case imageUndecodable(pageID: UUID)
    /// Decoded image has zero dimensions.
    case imageEmpty(pageID: UUID)
    /// Margin value leaves no drawable content area.
    case marginTooLarge(marginPoints: Double, availableWidth: Double, availableHeight: Double)
    /// The PDF context could not be created or written.
    case pdfContextFailed
    /// The output file could not be written or verified.
    case outputWriteFailed
    /// Disk space is insufficient for the estimated output.
    case insufficientStorage
    /// The export was cancelled cooperatively.
    case cancelled
    /// Duplicate page IDs were found in the draft.
    case duplicatePageIDs
}
