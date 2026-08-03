#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers
    import WatakeDomain

    /// Bounded-concurrency, downsampled thumbnail loading for the page rail.
    /// Reads through the injected port, prefers the rectified asset and falls
    /// back to the immutable source on failure (mirroring
    /// `DocumentViewerModel`'s main-preview fallback), downsamples via ImageIO
    /// so full-resolution pixel buffers are never retained, and caps
    /// concurrent reads so a multi-page document cannot start one full-asset
    /// decode per thumbnail at once.
    actor DocumentPageThumbnailLoader {
        private let loader: any DocumentPageAssetLoading
        private let maxConcurrentLoads: Int
        private let maxPixelSize: Int

        private var cache: [UUID: Data] = [:]
        private var activeLoads = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(loader: any DocumentPageAssetLoading, maxConcurrentLoads: Int = 4, maxPixelSize: Int = 112) {
            self.loader = loader
            self.maxConcurrentLoads = maxConcurrentLoads
            self.maxPixelSize = maxPixelSize
        }

        func thumbnail(for page: DocumentPage) async throws -> Data {
            if let cached = cache[page.id] {
                return cached
            }
            await acquireSlot()
            defer { releaseSlot() }
            if let cached = cache[page.id] {
                return cached
            }
            let data = try await readDisplayAsset(page: page)
            let downsampled = try Self.downsample(data, maxPixelSize: maxPixelSize)
            cache[page.id] = downsampled
            return downsampled
        }

        private func readDisplayAsset(page: DocumentPage) async throws -> Data {
            if let rectified = page.rectified {
                do {
                    return try await loader.readAsset(rectified)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Derived asset missing/corrupt: fall back to the immutable source.
                }
            }
            return try await loader.readAsset(page.source)
        }

        private func acquireSlot() async {
            if activeLoads < maxConcurrentLoads {
                activeLoads += 1
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            activeLoads += 1
        }

        private func releaseSlot() {
            activeLoads -= 1
            if !waiters.isEmpty {
                waiters.removeFirst().resume()
            }
        }

        private static func downsample(_ data: Data, maxPixelSize: Int) throws -> Data {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw DocumentViewerError.pageAssetUndecodable
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw DocumentViewerError.pageAssetUndecodable
            }
            let output = NSMutableData()
            guard let writer = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw DocumentViewerError.pageAssetUndecodable
            }
            CGImageDestinationAddImage(writer, thumbnail, nil)
            guard CGImageDestinationFinalize(writer) else {
                throw DocumentViewerError.pageAssetUndecodable
            }
            return output as Data
        }
    }
#endif
