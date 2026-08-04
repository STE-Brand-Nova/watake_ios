#if canImport(UIKit)
    import SwiftUI
    import UIKit

    public struct PlatformImage {
        public let swiftUIImage: Image

        public init?(data: Data) {
            guard let uiImage = UIImage(data: data) else { return nil }
            swiftUIImage = Image(uiImage: uiImage)
        }
    }
#elseif canImport(AppKit)
    import AppKit
    import SwiftUI

    public struct PlatformImage {
        public let swiftUIImage: Image

        public init?(data: Data) {
            guard let nsImage = NSImage(data: data) else { return nil }
            swiftUIImage = Image(nsImage: nsImage)
        }
    }
#endif
