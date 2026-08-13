import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Result of adapting one user-selected source batch. Failed items are counted
/// so the UI never presents a silently incomplete import.
public struct CaptureImportBatch: Sendable, Equatable {
    public let media: [CaptureImportMedia]
    public let failedCount: Int

    public init(media: [CaptureImportMedia], failedCount: Int) {
        self.media = media
        self.failedCount = failedCount
    }
}

/// Source-specific adapters normalize Photos and Files bytes identically.
/// Filesystem access and image decoding run outside the UI actor.
public enum CaptureImportSourceAdapter {
    public static let maximumSelectionCount = 20

    public static func photos(data: [Data?]) async -> CaptureImportBatch {
        await normalizeOffMainActor(data)
    }

    public static func files(data: [Data?]) async -> CaptureImportBatch {
        await normalizeOffMainActor(data)
    }

    public static func files(urls: [URL]) async -> CaptureImportBatch {
        let worker = Task.detached(priority: .userInitiated) {
            var data: [Data?] = []
            data.reserveCapacity(urls.count)
            for url in urls {
                if Task.isCancelled {
                    return CaptureImportBatch(media: [], failedCount: 0)
                }
                guard url.startAccessingSecurityScopedResource() else {
                    data.append(nil)
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }
                data.append(try? Data(contentsOf: url, options: .mappedIfSafe))
            }
            return normalize(data)
        }

        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func normalize(_ data: [Data?]) -> CaptureImportBatch {
        var media: [CaptureImportMedia] = []
        media.reserveCapacity(data.count)
        var failedCount = 0

        for item in data {
            guard let item, let normalized = normalizedMedia(from: item) else {
                failedCount += 1
                continue
            }
            media.append(normalized)
        }

        return CaptureImportBatch(media: media, failedCount: failedCount)
    }

    private static func normalizeOffMainActor(_ data: [Data?]) async -> CaptureImportBatch {
        let worker = Task.detached(priority: .userInitiated) {
            normalize(data)
        }
        return await worker.value
    }

    private static func normalizedMedia(from data: Data) -> CaptureImportMedia? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String),
              let mediaType = type.preferredMIMEType,
              let fileExtension = type.preferredFilenameExtension else { return nil }
        guard CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return nil }
        return CaptureImportMedia(data: data, mediaType: mediaType, fileExtension: fileExtension)
    }
}
