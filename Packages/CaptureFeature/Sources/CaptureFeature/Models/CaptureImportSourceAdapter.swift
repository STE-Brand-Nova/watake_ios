import CoreGraphics
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

public struct CaptureImportFile: Sendable, Equatable {
    public let data: Data
    public let fileExtension: String?

    public init(data: Data, fileExtension: String? = nil) {
        self.data = data
        self.fileExtension = fileExtension
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

    public static func files(items: [CaptureImportFile?]) async -> CaptureImportBatch {
        await normalizeFilesOffMainActor(items)
    }

    public static func files(urls: [URL]) async -> CaptureImportBatch {
        let worker = Task.detached(priority: .userInitiated) {
            var files: [CaptureImportFile?] = []
            files.reserveCapacity(urls.count)
            for url in urls {
                if Task.isCancelled {
                    return CaptureImportBatch(media: [], failedCount: 0)
                }
                guard url.startAccessingSecurityScopedResource() else {
                    files.append(nil)
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try? Data(contentsOf: url, options: .mappedIfSafe)
                files.append(data.map { CaptureImportFile(data: $0, fileExtension: url.pathExtension) })
            }
            return normalizeFiles(files)
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

    private static func normalizeFilesOffMainActor(_ files: [CaptureImportFile?]) async -> CaptureImportBatch {
        let worker = Task.detached(priority: .userInitiated) {
            normalizeFiles(files)
        }
        return await worker.value
    }

    private static func normalizeFiles(_ files: [CaptureImportFile?]) -> CaptureImportBatch {
        var media: [CaptureImportMedia] = []
        var failedCount = 0
        for file in files {
            guard let file else {
                failedCount += 1
                continue
            }
            let pages = normalizedMedia(from: file)
            if pages.isEmpty {
                failedCount += 1
            } else {
                media.append(contentsOf: pages)
            }
        }
        return CaptureImportBatch(media: media, failedCount: failedCount)
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

    private static func normalizedMedia(from file: CaptureImportFile) -> [CaptureImportMedia] {
        guard let provider = CGDataProvider(data: file.data as CFData) else { return [] }
        if let pdf = CGPDFDocument(provider) {
            return rasterizedPages(from: pdf)
        }
        guard let media = normalizedMedia(from: file.data) else { return [] }
        return [media]
    }

    private static func rasterizedPages(from pdf: CGPDFDocument) -> [CaptureImportMedia] {
        guard pdf.numberOfPages > 0 else { return [] }
        var pages: [CaptureImportMedia] = []
        pages.reserveCapacity(pdf.numberOfPages)
        for index in 1 ... pdf.numberOfPages {
            guard !Task.isCancelled, let page = pdf.page(at: index), let data = rasterize(page: page) else {
                return []
            }
            pages.append(CaptureImportMedia(data: data, mediaType: "image/png", fileExtension: "png"))
        }
        return pages
    }

    private static func rasterize(page: CGPDFPage) -> Data? {
        let bounds = page.getBoxRect(.mediaBox).standardized
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let maximumDimension: CGFloat = 2400
        let scale = min(2, maximumDimension / max(bounds.width, bounds.height))
        let width = max(1, Int((bounds.width * scale).rounded()))
        let height = max(1, Int((bounds.height * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        let drawingRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: drawingRect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        context.restoreGState()
        guard let image = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
