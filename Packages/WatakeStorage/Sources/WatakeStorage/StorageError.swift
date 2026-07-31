import Foundation

public enum StorageError: Error, Equatable, Sendable {
    case ioFailure
    case cryptoFailure
    case invalidRecord
    case encodingFailed
    case keychainUnavailable
    case notFound
    case documentNotInTrash
    case folderReassignmentUnsupported
    case assetIntegrityMismatch
    case owningFolderUnavailable
}
