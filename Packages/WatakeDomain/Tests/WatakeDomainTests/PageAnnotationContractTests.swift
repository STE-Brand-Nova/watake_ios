import Foundation
import Testing
@testable import WatakeDomain

@Suite("Page annotation contract")
struct PageAnnotationContractTests {
    @Test func roundTripPreservesLayerAndLowercaseIdentity() throws {
        let annotationID = try #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let annotation = PageAnnotation(
            id: annotationID, kind: .text,
            transform: .init(centerX: 0.5, centerY: 0.4, width: 0.6, height: 0.1),
            opacity: 0.8, zIndex: 0,
            text: AnnotationText(text: "Synthetic annotation", isBold: true)
        )
        let page = DocumentPage(id: UUID(), index: 0, source: asset(), annotations: [annotation])
        let data = try WatakeContractCoding.makeJSONEncoder().encode(page)
        let json = try #require(String(data: data, encoding: .utf8))
        let decoded = try WatakeContractCoding.makeJSONDecoder().decode(DocumentPage.self, from: data)
        #expect(json.contains(annotationID.uuidString.lowercased()))
        #expect(decoded.annotations == [annotation])
    }

    @Test func legacyPageWithoutAnnotationsDecodesEmpty() throws {
        let page = DocumentPage(id: UUID(), index: 0, source: asset())
        let encoded = try WatakeContractCoding.makeJSONEncoder().encode(page)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "annotations")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try WatakeContractCoding.makeJSONDecoder().decode(DocumentPage.self, from: legacy)
        #expect(decoded.annotations.isEmpty)
    }

    @Test func legacyImageAnnotationWithoutFlipFieldsDefaultsToUnflipped() throws {
        let image = asset()
        let annotation = PageAnnotation(
            id: UUID(), kind: .image,
            transform: .init(centerX: 0.5, centerY: 0.5, width: 0.4, height: 0.3),
            zIndex: 0, image: image,
            isFlippedHorizontally: true,
            isFlippedVertically: true
        )
        let encoded = try WatakeContractCoding.makeJSONEncoder().encode(annotation)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["isFlippedHorizontally"] as? Bool == true)
        #expect(object["isFlippedVertically"] as? Bool == true)
        object.removeValue(forKey: "isFlippedHorizontally")
        object.removeValue(forKey: "isFlippedVertically")

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try WatakeContractCoding.makeJSONDecoder().decode(PageAnnotation.self, from: legacy)

        #expect(!decoded.isFlippedHorizontally)
        #expect(!decoded.isFlippedVertically)
    }

    @Test func duplicateLayerIdentityFailsValidation() {
        let id = UUID()
        let page = DocumentPage(
            id: UUID(), index: 0, source: asset(),
            annotations: [textAnnotation(id: id, zIndex: 0), textAnnotation(id: id, zIndex: 1)]
        )
        #expect(throws: DomainValidationError.duplicateAnnotationIDs) { try page.validate() }
    }

    private func textAnnotation(id: UUID, zIndex: Int) -> PageAnnotation {
        PageAnnotation(
            id: id, kind: .text,
            transform: .init(centerX: 0.5, centerY: 0.5, width: 0.5, height: 0.1),
            zIndex: zIndex, text: AnnotationText(text: "Synthetic")
        )
    }

    private func asset() -> AssetReference {
        AssetReference(
            id: UUID(), relativePath: "source.jpg", sha256Hex: String(repeating: "a", count: 64),
            byteSize: 1, mediaType: "image/jpeg"
        )
    }
}
