import Foundation

public protocol StorageRootResolving: Sendable {
    func resolveRoot() throws -> URL
}

public struct ApplicationSupportRootResolver: StorageRootResolving {
    private let subdirectory: String

    public init(subdirectory: String = "Watake") {
        self.subdirectory = subdirectory
    }

    public func resolveRoot() throws -> URL {
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StorageError.ioFailure
        }
        let root = base.appendingPathComponent(subdirectory, isDirectory: true)
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw StorageError.ioFailure
        }
        return root
    }
}
