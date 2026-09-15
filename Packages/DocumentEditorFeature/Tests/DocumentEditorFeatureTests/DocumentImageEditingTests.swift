import Foundation
import Testing
import WatakeDomain
@testable import DocumentEditorFeature

@Suite("Document image editing")
struct DocumentImageEditingTests {
    @Test @MainActor
    func chosenImageWaitsForPagePlacementBeforeCreatingAnnotation() async {
        let (model, _) = EditorFixture().makeModel()

        #expect(model.prepareImagePlacement(
            data: Data("image".utf8),
            mediaType: "image/png",
            fileExtension: "png",
            aspectRatio: 2
        ))
        #expect(model.selectedPage?.annotations.isEmpty == true)
        #expect(model.pendingImagePlacement?.aspectRatio == 2)

        let transform = AnnotationTransform(centerX: 0.4, centerY: 0.6, width: 0.5, height: 0.25)
        #expect(await model.placePendingImage(transform: transform))
        #expect(model.pendingImagePlacement == nil)
        #expect(model.selectedAnnotation?.kind == .image)
        #expect(model.selectedAnnotation?.transform == transform)
        #expect(model.tool == .select)
    }

    @Test @MainActor
    func cancelImagePlacementDoesNotCreateAHistoryCommand() {
        let (model, _) = EditorFixture().makeModel()
        _ = model.prepareImagePlacement(
            data: Data("image".utf8),
            mediaType: "image/png",
            fileExtension: "png",
            aspectRatio: 1
        )

        model.cancelImagePlacement()

        #expect(model.pendingImagePlacement == nil)
        #expect(model.selectedPage?.annotations.isEmpty == true)
        #expect(!model.canUndo)
        #expect(model.tool == .select)
    }

    @Test @MainActor
    func replaceImagePreservesGeometryRotationAndFlipState() async throws {
        let (model, _) = EditorFixture().makeModel()
        #expect(await model.importImage(data: Data("first".utf8), mediaType: "image/png", fileExtension: "png"))
        model.transformSelected(centerX: 0.3, centerY: 0.7, width: 0.4, height: 0.2, rotationDelta: 37)
        model.flipSelectedImageHorizontally()
        let before = try #require(model.selectedAnnotation)

        #expect(await model.replaceSelectedImage(
            data: Data("replacement".utf8),
            mediaType: "image/jpeg",
            fileExtension: "jpg"
        ))
        let after = try #require(model.selectedAnnotation)

        #expect(after.image?.id != before.image?.id)
        #expect(after.transform == before.transform)
        #expect(after.isFlippedHorizontally)
        #expect(!after.isFlippedVertically)
    }

    @Test @MainActor
    func imageFlipAndQuarterTurnAreUndoable() async {
        let (model, _) = EditorFixture().makeModel()
        #expect(await model.importImage(data: Data("image".utf8), mediaType: "image/png", fileExtension: "png"))

        model.flipSelectedImageVertically()
        model.rotateSelectedImage(by: 90)

        #expect(model.selectedAnnotation?.isFlippedVertically == true)
        #expect(model.selectedAnnotation?.transform.rotation == 90)
        model.undo()
        #expect(model.selectedPage?.annotations.first?.transform.rotation == 0)
        #expect(model.selectedPage?.annotations.first?.isFlippedVertically == true)
        model.undo()
        #expect(model.selectedPage?.annotations.first?.isFlippedVertically == false)
    }

    @Test
    func imageTapAndDragPlacementPreserveSourceAspectRatio() {
        let pageSize = CGSize(width: 500, height: 1000)
        let tap = DocumentImageInteraction.placement(
            from: CGPoint(x: 250, y: 500),
            to: CGPoint(x: 252, y: 502),
            imageAspectRatio: 2,
            pageSize: pageSize
        )
        let drag = DocumentImageInteraction.placement(
            from: CGPoint(x: 100, y: 200),
            to: CGPoint(x: 400, y: 500),
            imageAspectRatio: 2,
            pageSize: pageSize
        )

        #expect(abs((tap.width * 500) / (tap.height * 1000) - 2) < 0.000_001)
        #expect(abs((drag.width * 500) / (drag.height * 1000) - 2) < 0.000_001)
    }

    @Test
    func imageCornerResizeKeepsOppositeCornerAndAspectRatio() {
        let pageSize = CGSize(width: 500, height: 1000)
        let start = AnnotationTransform(centerX: 0.5, centerY: 0.5, width: 0.4, height: 0.1)
        let resized = DocumentImageInteraction.resized(
            from: start,
            corner: .bottomTrailing,
            location: CGPoint(x: 400, y: 650),
            pageSize: pageSize
        )
        let originalTopLeft = CGPoint(x: 150, y: 450)
        let resizedTopLeft = CGPoint(
            x: (resized.centerX - resized.width / 2) * pageSize.width,
            y: (resized.centerY - resized.height / 2) * pageSize.height
        )

        #expect(hypot(resizedTopLeft.x - originalTopLeft.x, resizedTopLeft.y - originalTopLeft.y) < 0.000_001)
        #expect(abs((resized.width * 500) / (resized.height * 1000) - 2) < 0.000_001)
    }

    @Test
    func imageRotationSnapsOnlyNearCardinalAngles() {
        #expect(DocumentImageInteraction.snappedRotation(86) == 90)
        #expect(DocumentImageInteraction.snappedRotation(98) == 98)
        #expect(DocumentImageInteraction.snappedRotation(179) == -180)
    }

    @Test @MainActor
    func imageRotationNeverRecentersImage() async throws {
        let (model, _) = EditorFixture().makeModel()
        #expect(await model.importImage(data: Data("image".utf8), mediaType: "image/png", fileExtension: "png"))
        model.transformSelected(centerX: 0.5149, centerY: 0.503)

        model.rotateSelectedImage(by: 90)

        let transform = try #require(model.selectedAnnotation?.transform)
        #expect(transform.centerX == 0.5149)
        #expect(transform.centerY == 0.503)
        #expect(transform.rotation == 90)
    }

    @Test @MainActor
    func duplicatedImageIsVisiblyOffsetAndIndependent() async throws {
        let (model, _) = EditorFixture().makeModel()
        #expect(await model.importImage(data: Data("image".utf8), mediaType: "image/png", fileExtension: "png"))
        let original = try #require(model.selectedAnnotation)

        model.duplicateSelected()

        let duplicate = try #require(model.selectedAnnotation)
        #expect(duplicate.id != original.id)
        #expect(duplicate.image == original.image)
        #expect(duplicate.transform.centerX != original.transform.centerX)
        #expect(duplicate.transform.centerY != original.transform.centerY)
    }

    @Test
    func rotatedResizeNearPageEdgeKeepsOppositeCornerAnchored() {
        let pageSize = CGSize(width: 500, height: 1000)
        let start = AnnotationTransform(centerX: 0.85, centerY: 0.85, width: 0.2, height: 0.1, rotation: 30)
        let originalAnchor = oppositeCorner(of: start, resizing: .bottomTrailing, pageSize: pageSize)

        let resized = DocumentImageInteraction.resized(
            from: start,
            corner: .bottomTrailing,
            location: CGPoint(x: 1500, y: 2000),
            pageSize: pageSize
        )
        let resizedAnchor = oppositeCorner(of: resized, resizing: .bottomTrailing, pageSize: pageSize)

        #expect(hypot(resizedAnchor.x - originalAnchor.x, resizedAnchor.y - originalAnchor.y) < 0.000_001)
        #expect(resized.centerX <= 1)
        #expect(resized.centerY <= 1)
        #expect(abs((resized.width * pageSize.width) / (resized.height * pageSize.height) - 1) < 0.000_001)
    }

    private func oppositeCorner(
        of transform: AnnotationTransform,
        resizing corner: ImageResizeCorner,
        pageSize: CGSize
    ) -> CGPoint {
        let localOffset = CGPoint(
            x: -corner.horizontalSign * transform.width * pageSize.width / 2,
            y: -corner.verticalSign * transform.height * pageSize.height / 2
        )
        let radians = transform.rotation * .pi / 180
        let rotatedOffset = CGPoint(
            x: cos(radians) * localOffset.x - sin(radians) * localOffset.y,
            y: sin(radians) * localOffset.x + cos(radians) * localOffset.y
        )
        return CGPoint(
            x: transform.centerX * pageSize.width + rotatedOffset.x,
            y: transform.centerY * pageSize.height + rotatedOffset.y
        )
    }
}
