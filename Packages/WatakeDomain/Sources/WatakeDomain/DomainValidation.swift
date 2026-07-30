import Foundation

enum DomainValidation {
    static func validateUUIDString(_ value: String) throws -> UUID {
        let isLowercase = value == value.lowercased()
        guard isLowercase, let uuid = UUID(uuidString: value) else {
            throw DomainValidationError.invalidUUIDString(value)
        }
        return uuid
    }

    static func validateTrimmed(_ value: String, field: String, maxLength: Int) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainValidationError.emptyName(field: field)
        }
        guard trimmed.count <= maxLength else {
            throw DomainValidationError.nameTooLong(field: field, maxLength: maxLength)
        }
        guard value == trimmed else {
            throw DomainValidationError.emptyName(field: field)
        }
    }

    static func validateColorHex(_ value: String) throws {
        let isValid = value.count == 7 &&
            value.first == "#" &&
            value.dropFirst().allSatisfy(\.isHexDigit)
        guard isValid else {
            throw DomainValidationError.invalidColorHex(value)
        }
    }

    static func validateDocumentPages(_ pages: [DocumentPage]) throws {
        guard !pages.isEmpty else {
            throw DomainValidationError.documentRequiresPage
        }
        try validateIndexes(pages.map(\.index))
    }

    static func validateOrderIndex(_ index: Int) throws {
        guard index >= 0 else {
            throw DomainValidationError.negativeOrderIndex(index)
        }
    }

    static func validateUniqueTagIDs(_ tagIds: [UUID]) throws {
        guard Set(tagIds).count == tagIds.count else {
            throw DomainValidationError.duplicateTagIDs
        }
    }

    static func validateRenditionPages(_ pages: [RenditionPage]) throws {
        try validateIndexes(pages.map(\.index))
    }

    static func validateAssetPath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let isRelative = !path.isEmpty && !path.hasPrefix("/") && !isWindowsAbsolutePath(path)
        guard isRelative else {
            throw DomainValidationError.invalidAssetPath(path)
        }
        guard !components.contains("..") else {
            throw DomainValidationError.invalidAssetPath(path)
        }
        let isNormalized = components.allSatisfy { !$0.isEmpty && $0 != "." } && !path.contains("\\")
        guard isNormalized else {
            throw DomainValidationError.invalidAssetPath(path)
        }
    }

    static func validateSHA256(_ value: String) throws {
        let isValid = value.count == 64 && value.allSatisfy(isLowercaseHexDigit)
        guard isValid else {
            throw DomainValidationError.invalidSHA256(value)
        }
    }

    static func validateByteSize(_ value: Int) throws {
        guard value >= 0 else {
            throw DomainValidationError.invalidByteSize(value)
        }
    }

    static func validateOpacity(_ value: Double) throws {
        guard value >= 0, value <= 1 else {
            throw DomainValidationError.opacityOutOfRange(value)
        }
    }

    static func validateSchemaVersion(_ value: Int) throws {
        guard value >= 1 else {
            throw DomainValidationError.invalidSchemaVersion(value)
        }
    }

    static func validateRotation(_ value: Double) throws {
        guard value >= -180, value <= 180 else {
            throw DomainValidationError.rotationOutOfRange(value)
        }
    }

    private static func validateIndexes(_ indexes: [Int]) throws {
        let expectedIndexes = Array(0 ..< indexes.count)
        guard indexes.sorted() == expectedIndexes else {
            throw DomainValidationError.pageIndexesNotContiguous
        }
    }

    private static func isWindowsAbsolutePath(_ path: String) -> Bool {
        guard path.count > 2 else {
            return false
        }
        let start = path.startIndex
        let second = path.index(after: start)
        return path[second] == ":" && path[start].isLetter
    }

    private static func isLowercaseHexDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9" || character >= "a" && character <= "f"
    }
}
