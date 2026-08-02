import CoreText
import Foundation

/// Deterministic font policy: use the requested family name only when the
/// platform's font catalog actually has it installed; otherwise fall back to
/// a font guaranteed present on every supported Apple platform. This never
/// throws, so a missing/typo'd font name can never block a render.
enum WatermarkFontResolver {
    static let fallbackFamilyName = "Helvetica"

    static func resolveFont(named requestedName: String, pointSize: Double) -> CTFont {
        let familyName = isFamilyAvailable(requestedName) ? requestedName : fallbackFamilyName
        return CTFontCreateWithName(familyName as CFString, pointSize, nil)
    }

    private static func isFamilyAvailable(_ name: String) -> Bool {
        guard let families = CTFontManagerCopyAvailableFontFamilyNames() as? [String] else {
            return false
        }
        return families.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}
