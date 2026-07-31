import Foundation

struct AtomicFileWriter {
    private let fileManager: FileManager
    private let protectionApplier: FileProtectionApplying
    private let temporaryDirectory: URL

    init(fileManager: FileManager, protectionApplier: FileProtectionApplying, temporaryDirectory: URL) {
        self.fileManager = fileManager
        self.protectionApplier = protectionApplier
        self.temporaryDirectory = temporaryDirectory
    }

    func write(_ data: Data, to destination: URL) throws {
        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw StorageError.ioFailure
        }

        let temporaryURL = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)

        do {
            try data.write(to: temporaryURL, options: .atomic)
            try protectionApplier.applyProtection(at: temporaryURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error is StorageError ? error : StorageError.ioFailure
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw StorageError.ioFailure
        }
    }
}
