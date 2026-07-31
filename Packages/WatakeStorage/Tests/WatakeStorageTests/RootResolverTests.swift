import Foundation
import Testing
@testable import WatakeStorage

@Suite("Production root resolver")
struct RootResolverTests {
    @Test("resolves under Application Support, never Documents or a user-visible path")
    func resolvesUnderApplicationSupport() throws {
        let subdirectory = "WatakeStorageTests-\(UUID().uuidString)"
        let resolver = ApplicationSupportRootResolver(subdirectory: subdirectory)
        let root = try resolver.resolveRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let expectedBase = try #require(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )

        #expect(root.path.hasPrefix(expectedBase.path))
        #expect(root.lastPathComponent == subdirectory)
        #expect(!root.path.contains("/Documents/"))
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
