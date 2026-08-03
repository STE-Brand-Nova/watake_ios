#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// Thin decode wrapper so preview/thumbnail views share one failure path
    /// for undecodable page asset data.
    struct PlatformImage {
        let swiftUIImage: Image

        init?(data: Data) {
            guard let uiImage = UIImage(data: data) else { return nil }
            swiftUIImage = Image(uiImage: uiImage)
        }
    }
#endif
