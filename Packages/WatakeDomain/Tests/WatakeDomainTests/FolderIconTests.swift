import Foundation
import Testing
@testable import WatakeDomain

@Suite("Folder icons")
struct FolderIconTests {
    @Test("folder icon identifier must be stable kebab-case")
    func folderRejectsInvalidIconIdentifier() {
        let folder = Folder(
            id: UUID(),
            name: "Receipts",
            colorHex: "#3B82F6",
            iconId: "SF Folder",
            createdAt: .now
        )

        #expect(throws: DomainValidationError.invalidIconID("SF Folder")) {
            try folder.validate()
        }
    }

    @Test("legacy folder metadata defaults to folder icon")
    func legacyFolderDefaultsIcon() throws {
        let json = Data("""
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Archive",
          "colorHex": "#3B82F6",
          "createdAt": "2026-09-25T00:00:00Z"
        }
        """.utf8)

        let folder = try WatakeContractCoding.makeJSONDecoder().decode(Folder.self, from: json)

        #expect(folder.iconId == FolderIconCatalog.defaultIdentifier)
    }

    @Test("all catalog identifiers must be valid icon IDs")
    func allCatalogIdentifiersAreValid() {
        #expect(throws: Never.self) {
            for id in FolderIconCatalog.identifiers {
                try DomainValidation.validateIconID(id)
            }
        }
    }

    @Test("validateIconID rejects empty, uppercase, and malformed strings")
    func validateIconIDRejectsMalformed() {
        #expect(throws: DomainValidationError.invalidIconID("")) {
            try DomainValidation.validateIconID("")
        }
        #expect(throws: DomainValidationError.invalidIconID("Folder")) {
            try DomainValidation.validateIconID("Folder")
        }
        #expect(throws: DomainValidationError.invalidIconID("folder_icon")) {
            try DomainValidation.validateIconID("folder_icon")
        }
        #expect(throws: DomainValidationError.invalidIconID("-folder")) {
            try DomainValidation.validateIconID("-folder")
        }
        let tooLong = String(repeating: "a", count: 65)
        #expect(throws: DomainValidationError.invalidIconID(tooLong)) {
            try DomainValidation.validateIconID(tooLong)
        }
    }
}
