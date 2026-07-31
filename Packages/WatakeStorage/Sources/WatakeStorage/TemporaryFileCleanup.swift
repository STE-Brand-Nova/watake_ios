import Foundation

enum TemporaryFileCleanup {
    static func removeStaleTemporaryFiles(under root: URL, fileManager: FileManager) {
        let temporaryDirectory = StorageLayout.temporaryDirectory(root)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for url in contents {
            try? fileManager.removeItem(at: url)
        }
    }
}
