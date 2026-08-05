#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers
    import WatakeDomain

    /// Regenerable thumbnails live only in Caches. Cache keys include source
    /// content hash, so immutable source changes cannot display stale previews.
    public actor ThumbnailCache {
        private let fileManager: FileManager
        private let directory: URL

        public init(fileManager: FileManager = .default, directory: URL? = nil) throws {
            self.fileManager = fileManager
            if let directory {
                self.directory = directory
            } else if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
                self.directory = caches.appendingPathComponent("Watake/thumbnails", isDirectory: true)
            } else {
                throw ImportSaveError.cacheUnavailable
            }
            try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        }

        /// Returns the cached thumbnail for `source` if one exists and is
        /// still decodable, without generating a new one. Self-heals a
        /// corrupt cache entry by deleting it, so a caller that regenerates
        /// on `nil` never keeps re-reading the same bad file.
        public func cachedThumbnailIfPresent(for source: AssetReference, maxPixelSize: Int = 512) -> Data? {
            readValidCachedThumbnail(at: cacheURL(for: source, maxPixelSize: maxPixelSize))
        }

        public func thumbnail(for source: AssetReference, data: Data, maxPixelSize: Int = 512) throws -> Data {
            let url = cacheURL(for: source, maxPixelSize: maxPixelSize)
            if let cached = readValidCachedThumbnail(at: url) {
                return cached
            }
            guard let image = CGImageSourceCreateWithData(data as CFData, nil) else { throw ImportSaveError.thumbnailFailed }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary) else {
                throw ImportSaveError.thumbnailFailed
            }
            let output = NSMutableData()
            guard let writer = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw ImportSaveError.thumbnailFailed
            }
            CGImageDestinationAddImage(writer, thumbnail, nil)
            guard CGImageDestinationFinalize(writer) else { throw ImportSaveError.thumbnailFailed }
            try (output as Data).write(to: url, options: .atomic)
            return output as Data
        }

        private func cacheURL(for source: AssetReference, maxPixelSize: Int) -> URL {
            directory.appendingPathComponent("\(source.sha256Hex)-\(maxPixelSize).jpg")
        }

        private func readValidCachedThumbnail(at url: URL) -> Data? {
            guard let cached = try? Data(contentsOf: url) else { return nil }
            // `CGImageSourceCreateWithData` alone accepts near-arbitrary bytes
            // without validating the payload; only an actual decode attempt
            // reveals a truncated/corrupt cache file.
            let isDecodable = CGImageSourceCreateWithData(cached as CFData, nil)
                .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } != nil
            guard isDecodable else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            return cached
        }
    }
#endif
