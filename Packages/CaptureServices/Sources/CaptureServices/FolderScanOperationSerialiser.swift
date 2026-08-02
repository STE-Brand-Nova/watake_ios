import Foundation

/// Serializes complete scan-save operations for each folder. Inject one shared
/// instance for every scanner using the same repository; no global singleton
/// is used.
public actor FolderScanOperationSerialiser {
    private var activeFolderIDs: Set<UUID> = []
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    public init() {}

    public func perform<Value: Sendable>(
        for folderID: UUID,
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        await acquire(folderID)
        do {
            let value = try await operation()
            release(folderID)
            return value
        } catch {
            release(folderID)
            throw error
        }
    }

    private func acquire(_ folderID: UUID) async {
        guard !activeFolderIDs.contains(folderID) else {
            await withCheckedContinuation { continuation in
                waiters[folderID, default: []].append(continuation)
            }
            return
        }
        activeFolderIDs.insert(folderID)
    }

    private func release(_ folderID: UUID) {
        guard var folderWaiters = waiters[folderID], !folderWaiters.isEmpty else {
            activeFolderIDs.remove(folderID)
            return
        }
        let next = folderWaiters.removeFirst()
        waiters[folderID] = folderWaiters.isEmpty ? nil : folderWaiters
        next.resume()
    }
}
