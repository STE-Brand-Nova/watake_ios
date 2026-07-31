import Foundation

public protocol FileProtectionApplying: Sendable {
    func applyProtection(at url: URL) throws
}

public struct UntilFirstUnlockFileProtection: FileProtectionApplying {
    public init() {}

    public func applyProtection(at url: URL) throws {
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            throw StorageError.ioFailure
        }
    }
}
