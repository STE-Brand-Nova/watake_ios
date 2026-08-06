import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WatakeDomain

public enum WatermarkImageImportError: Error, Equatable, Sendable {
    case undecodable
    case unsupportedMediaType
    case unreasonableSize

    public var message: String {
        switch self {
        case .undecodable: "This image could not be opened."
        case .unsupportedMediaType: "Choose a PNG or JPEG image."
        case .unreasonableSize: "Choose a smaller image."
        }
    }
}

public struct ImportedWatermarkImage: Equatable, Sendable {
    public let data: Data
    public let assetReference: AssetReference

    public init(data: Data, assetReference: AssetReference) {
        self.data = data
        self.assetReference = assetReference
    }
}

/// Injectable, platform-detail boundary for validating picker bytes.
public protocol WatermarkImageImporting: Sendable {
    func importImage(data: Data) async throws -> ImportedWatermarkImage
}

public struct WatermarkImageImporter: WatermarkImageImporting {
    public static let maximumByteCount = 20 * 1024 * 1024
    public static let maximumPixelCount = 25_000_000

    public init() {}

    public func importImage(data: Data) async throws -> ImportedWatermarkImage {
        guard data.count <= Self.maximumByteCount else { throw WatermarkImageImportError.unreasonableSize }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier) else { throw WatermarkImageImportError.undecodable }

        let mediaType: String
        let fileExtension: String
        switch type {
        case .png:
            mediaType = "image/png"
            fileExtension = "png"
        case .jpeg:
            mediaType = "image/jpeg"
            fileExtension = "jpg"
        default:
            throw WatermarkImageImportError.unsupportedMediaType
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw WatermarkImageImportError.undecodable
        }
        guard let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else { throw WatermarkImageImportError.undecodable }
        guard width <= Self.maximumPixelCount / height else {
            throw WatermarkImageImportError.unreasonableSize
        }
        guard CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw WatermarkImageImportError.undecodable }

        let id = UUID()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let reference = AssetReference(
            id: id,
            relativePath: "watermark-assets/\(id.uuidString.lowercased()).\(fileExtension)",
            sha256Hex: digest,
            byteSize: data.count,
            mediaType: mediaType
        )
        return ImportedWatermarkImage(data: data, assetReference: reference)
    }
}
