import Foundation
import WatakeDomain

public enum DocumentEditorTool: String, CaseIterable, Identifiable, Sendable {
    case select
    case text
    case signature
    case image
    case highlight

    public var id: String {
        rawValue
    }
}

public enum DocumentEditorSaveState: Equatable, Sendable {
    case idle
    case saving
    case savedCopy
    case failed
}

public struct PendingImagePlacement: Equatable, Sendable {
    public let id: UUID
    public let data: Data
    public let mediaType: String
    public let fileExtension: String
    public let aspectRatio: Double

    public init(id: UUID, data: Data, mediaType: String, fileExtension: String, aspectRatio: Double) {
        self.id = id
        self.data = data
        self.mediaType = mediaType
        self.fileExtension = fileExtension
        self.aspectRatio = aspectRatio
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

struct PageHistory: Sendable {
    var undo: [[PageAnnotation]] = []
    var redo: [[PageAnnotation]] = []

    mutating func record(_ before: [PageAnnotation]) {
        undo.append(before)
        if undo.count > 100 {
            undo.removeFirst(undo.count - 100)
        }
        redo.removeAll()
    }

    mutating func undo(current: [PageAnnotation]) -> [PageAnnotation]? {
        guard let previous = undo.popLast() else { return nil }
        redo.append(current)
        return previous
    }

    mutating func redo(current: [PageAnnotation]) -> [PageAnnotation]? {
        guard let next = redo.popLast() else { return nil }
        undo.append(current)
        return next
    }
}

struct PageThumbnailCacheEntry: Sendable {
    let page: DocumentPage
    let data: Data
}
