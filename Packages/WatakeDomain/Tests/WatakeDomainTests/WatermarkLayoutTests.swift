import Foundation
import Testing
@testable import WatakeDomain

struct PositionExpectation {
    let position: WatermarkPosition
    let horizontal: WatermarkHorizontalAlignment
    let vertical: WatermarkVerticalAlignment
}

private func makeTextLayer(
    text: String = "Confidential",
    enabled: Bool = true,
    fontName: String = "Helvetica",
    sizePreset: WatermarkSizePreset = .medium,
    colorHex: String = "#FF0000",
    rotation: Double = 0,
    opacity: Double = 1
) -> WatermarkTextLayer {
    WatermarkTextLayer(
        text: text,
        enabled: enabled,
        fontName: fontName,
        sizePreset: sizePreset,
        colorHex: colorHex,
        rotation: rotation,
        opacity: opacity
    )
}

private func makeConfig(
    body: WatermarkTextLayer? = makeTextLayer(),
    heading: WatermarkTextLayer? = nil,
    caption: WatermarkTextLayer? = nil,
    image: WatermarkImageLayer? = nil,
    globalPosition: WatermarkPosition = .center,
    globalRotation: Double = 0,
    globalOpacity: Double = 1
) -> WatermarkConfig {
    WatermarkConfig(
        automatic: false,
        heading: heading,
        body: body,
        caption: caption,
        image: image,
        globalPosition: globalPosition,
        globalRotation: globalRotation,
        globalOpacity: globalOpacity
    )
}

struct WatermarkLayoutTests {
    @Test func textLayerRenderEligibilityAndCompositionOrderAreShared() {
        let heading = makeTextLayer(text: "Heading")
        let body = makeTextLayer(text: " ")
        let caption = makeTextLayer(text: "Caption", enabled: false)
        let config = makeConfig(body: body, heading: heading, caption: caption)

        #expect(heading.isRenderable)
        #expect(!body.isRenderable)
        #expect(!caption.isRenderable)
        #expect(config.renderableTextLayersInCompositionOrder.map(\.text) == ["Heading"])
    }

    @Test func mapsAllNinePositionsToDistinctAnchorsAndAlignments() {
        let expectations: [PositionExpectation] = [
            PositionExpectation(position: .topLeft, horizontal: .leading, vertical: .top),
            PositionExpectation(position: .topCenter, horizontal: .center, vertical: .top),
            PositionExpectation(position: .topRight, horizontal: .trailing, vertical: .top),
            PositionExpectation(position: .midLeft, horizontal: .leading, vertical: .center),
            PositionExpectation(position: .center, horizontal: .center, vertical: .center),
            PositionExpectation(position: .midRight, horizontal: .trailing, vertical: .center),
            PositionExpectation(position: .botLeft, horizontal: .leading, vertical: .bottom),
            PositionExpectation(position: .botCenter, horizontal: .center, vertical: .bottom),
            PositionExpectation(position: .botRight, horizontal: .trailing, vertical: .bottom)
        ]

        for expectation in expectations {
            let config = makeConfig(globalPosition: expectation.position)
            let layout = WatermarkLayoutCalculator.makeLayout(bodyLayer: makeTextLayer(), config: config)
            #expect(layout.horizontalAlignment == expectation.horizontal)
            #expect(layout.verticalAlignment == expectation.vertical)
            #expect(layout.normalizedAnchorX >= 0 && layout.normalizedAnchorX <= 1)
            #expect(layout.normalizedAnchorY >= 0 && layout.normalizedAnchorY <= 1)
        }
    }

    @Test func topPositionsAnchorNearTopOfPage() {
        let config = makeConfig(globalPosition: .topCenter)
        let layout = WatermarkLayoutCalculator.makeLayout(bodyLayer: makeTextLayer(), config: config)
        let anchor = layout.anchor(pageWidth: 1000, pageHeight: 2000)
        #expect(anchor.y > 1000)
    }

    @Test func bottomPositionsAnchorNearBottomOfPage() {
        let config = makeConfig(globalPosition: .botCenter)
        let layout = WatermarkLayoutCalculator.makeLayout(bodyLayer: makeTextLayer(), config: config)
        let anchor = layout.anchor(pageWidth: 1000, pageHeight: 2000)
        #expect(anchor.y < 1000)
    }

    @Test func sizePresetsMapToIncreasingFontFractions() {
        let small = WatermarkLayoutCalculator.makeLayout(
            bodyLayer: makeTextLayer(sizePreset: .small),
            config: makeConfig()
        )
        let medium = WatermarkLayoutCalculator.makeLayout(
            bodyLayer: makeTextLayer(sizePreset: .medium),
            config: makeConfig()
        )
        let large = WatermarkLayoutCalculator.makeLayout(
            bodyLayer: makeTextLayer(sizePreset: .large),
            config: makeConfig()
        )

        #expect(small.normalizedFontSize < medium.normalizedFontSize)
        #expect(medium.normalizedFontSize < large.normalizedFontSize)
    }

    @Test func sizePresetMappingIsDeterministic() {
        let first = WatermarkLayoutCalculator.makeLayout(bodyLayer: makeTextLayer(sizePreset: .medium), config: makeConfig())
        let second = WatermarkLayoutCalculator.makeLayout(bodyLayer: makeTextLayer(sizePreset: .medium), config: makeConfig())
        #expect(first.normalizedFontSize == second.normalizedFontSize)
        #expect(first.fontPointSize(pageWidth: 1000, pageHeight: 2000) == second.fontPointSize(pageWidth: 1000, pageHeight: 2000))
    }

    @Test func combinesLayerAndGlobalOpacitySafelyWithinUnitRange() {
        let config = makeConfig(globalOpacity: 0.5)
        let layout = WatermarkLayoutCalculator.makeLayout(
            bodyLayer: makeTextLayer(opacity: 0.5),
            config: config
        )
        #expect(layout.opacity == 0.25)
        #expect(layout.opacity >= 0 && layout.opacity <= 1)
    }

    @Test func combinesLayerAndGlobalRotation() {
        let config = makeConfig(globalRotation: 30)
        let layout = WatermarkLayoutCalculator.makeLayout(
            bodyLayer: makeTextLayer(rotation: 15),
            config: config
        )
        #expect(layout.rotationDegrees == 45)
    }
}
