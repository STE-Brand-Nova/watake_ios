#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// Watermark-content conversion only. UI chrome continues using semantic
    /// DesignSystem colors.
    extension Color {
        init(watermarkHex: String) {
            let digits = watermarkHex.dropFirst(watermarkHex.hasPrefix("#") ? 1 : 0)
            let value = UInt64(digits, radix: 16) ?? 0
            self.init(
                .sRGB,
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                opacity: 1
            )
        }

        var watermarkHexRGB: String? {
            let color = UIColor(self)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
                return nil
            }
            return WatermarkHexColor.rgb(
                red: Double(red),
                green: Double(green),
                blue: Double(blue)
            )
        }
    }
#endif
