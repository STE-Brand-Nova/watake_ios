#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// Thin decode wrapper so preview/thumbnail views share one failure path
    /// for undecodable page asset data.
    struct PlatformImage {
        let swiftUIImage: Image
        let displaySize: CGSize

        init?(data: Data) {
            guard let uiImage = UIImage(data: data) else { return nil }
            swiftUIImage = Image(uiImage: uiImage)
            switch uiImage.imageOrientation {
            case .left, .leftMirrored, .right, .rightMirrored:
                displaySize = CGSize(width: uiImage.size.height, height: uiImage.size.width)
            default:
                displaySize = uiImage.size
            }
        }
    }
#endif
