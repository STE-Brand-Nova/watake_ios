import Foundation
import WatakeDomain

public enum WatermarkPresetNameValidation: Equatable, Sendable {
    case valid(String)
    case empty
    case tooLong

    public static func validate(_ name: String) -> Self {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.count <= 120 else { return .tooLong }
        return .valid(trimmed)
    }

    public var message: String? {
        switch self {
        case .valid: nil
        case .empty: "Enter a preset name."
        case .tooLong: "Preset names can be up to 120 characters."
        }
    }
}

public struct WatermarkPresetLibraryItem: Identifiable, Equatable, Sendable {
    public let preset: WatermarkPreset

    public init(preset: WatermarkPreset) {
        self.preset = preset
    }

    public var id: UUID {
        preset.id
    }

    public var isAvailable: Bool {
        true
    }

    public var enabledTextLayerTitles: [String] {
        [
            ("Heading", preset.config.heading),
            ("Body", preset.config.body),
            ("Caption", preset.config.caption)
        ]
        .compactMap { title, layer in layer?.isRenderable == true ? title : nil }
    }

    public var accessibilitySummary: String {
        let layers = enabledTextLayerTitles
        let image = preset.config.image?.enabled == true ? ["Image"] : []
        let enabled = layers + image
        return enabled.isEmpty ? "No enabled layers" : "Enabled layers: \(enabled.joined(separator: ", "))"
    }
}

public enum WatermarkPresetLibraryState: Equatable, Sendable {
    case idle
    case loading
    case empty
    case loaded([WatermarkPresetLibraryItem])
    case failure
}

public enum WatermarkPresetSaveState: Equatable, Sendable {
    case idle
    case saving
    case saved
    case invalidName(WatermarkPresetNameValidation)
    case conflict
    case imageUnsupported
    case failure
}

public enum WatermarkActivePresetState: Equatable, Sendable {
    case none
    case selected(id: UUID, name: String)
    case modified(id: UUID, name: String)

    public var label: String {
        switch self {
        case .none: "No preset selected"
        case .selected(_, let name): name
        case .modified(_, let name): "Modified from \(name)"
        }
    }
}

/// Default only for callers that have not composed app storage. It reveals no
/// storage details and lets the editor present a recoverable failure state.
public struct UnavailableWatermarkPresetStore: WatermarkPresetStore {
    public init() {}

    public func watermarkPresets() async throws -> [WatermarkPreset] {
        throw WatermarkPresetStoreError.unavailable
    }

    public func saveWatermarkPreset(_ preset: WatermarkPreset) async throws {
        throw WatermarkPresetStoreError.unavailable
    }
}

extension [WatermarkPreset] {
    func sortedForWatermarkLibrary() -> [WatermarkPreset] {
        sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return nameOrder == .orderedSame
                ? lhs.id.uuidString < rhs.id.uuidString
                : nameOrder == .orderedAscending
        }
    }
}
