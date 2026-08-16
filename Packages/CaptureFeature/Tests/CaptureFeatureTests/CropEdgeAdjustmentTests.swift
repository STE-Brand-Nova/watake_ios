import Testing
import WatakeDomain
@testable import CaptureFeature

struct CropEdgeAdjustmentTests {
    @Test
    func horizontalEdgeMovesBothConnectedYCoordinates() {
        let quad = sampleQuad()
        let moved = CropEdgeAdjustment.moved(quad, edge: .top, normalizedDelta: -0.1)

        #expect(moved.topLeft.x == quad.topLeft.x)
        #expect(moved.topRight.x == quad.topRight.x)
        #expect(moved.topLeft.y == quad.topLeft.y - 0.1)
        #expect(moved.topRight.y == quad.topRight.y - 0.1)
        #expect(moved.bottomLeft == quad.bottomLeft)
        #expect(moved.bottomRight == quad.bottomRight)
    }

    @Test
    func verticalEdgeMovesBothConnectedXCoordinates() {
        let quad = sampleQuad()
        let moved = CropEdgeAdjustment.moved(quad, edge: .right, normalizedDelta: -0.1)

        #expect(moved.topRight.x == quad.topRight.x - 0.1)
        #expect(moved.bottomRight.x == quad.bottomRight.x - 0.1)
        #expect(moved.topRight.y == quad.topRight.y)
        #expect(moved.bottomRight.y == quad.bottomRight.y)
        #expect(moved.topLeft == quad.topLeft)
        #expect(moved.bottomLeft == quad.bottomLeft)
    }

    @Test
    func edgeMovementCannotCrossOppositeEdgeOrImageBounds() {
        let quad = sampleQuad()
        let movedTop = CropEdgeAdjustment.moved(quad, edge: .top, normalizedDelta: -1)
        let movedLeft = CropEdgeAdjustment.moved(quad, edge: .left, normalizedDelta: 1)

        #expect(movedTop.topLeft.y > movedTop.bottomLeft.y)
        #expect(movedTop.topRight.y > movedTop.bottomRight.y)
        #expect(movedLeft.topLeft.x < movedLeft.topRight.x)
        #expect(movedLeft.bottomLeft.x < movedLeft.bottomRight.x)
    }

    private func sampleQuad() -> CropQuadrilateral {
        CropQuadrilateral(
            topLeft: NormalizedPoint(x: 0.2, y: 0.8),
            topRight: NormalizedPoint(x: 0.8, y: 0.75),
            bottomRight: NormalizedPoint(x: 0.85, y: 0.2),
            bottomLeft: NormalizedPoint(x: 0.15, y: 0.25)
        )
    }
}
