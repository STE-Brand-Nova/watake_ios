import XCTest
@testable import DesignSystem

final class ButtonStyleTests: XCTestCase {
    private func resolve(
        _ variant: WatakeButtonVariant,
        enabled: Bool = true,
        pressed: Bool = false
    ) -> WatakeButtonAppearance {
        WatakeButtonAppearance.resolve(variant: variant, isEnabled: enabled, isPressed: pressed)
    }

    // MARK: - Primary

    func testPrimaryDefault() {
        XCTAssertEqual(resolve(.primary).fill, .brandPrimary)
        XCTAssertEqual(resolve(.primary).foreground, .onPrimary)
    }

    func testPrimaryPressedUsesPressedFill() {
        XCTAssertEqual(resolve(.primary, pressed: true).fill, .brandPressed)
    }

    func testPrimaryDisabledIgnoresPressedAndUsesDisabledFill() {
        let disabledPressed = resolve(.primary, enabled: false, pressed: true)
        XCTAssertEqual(disabledPressed.fill, .brandDisabled)
        XCTAssertEqual(disabledPressed, resolve(.primary, enabled: false, pressed: false))
    }

    // MARK: - Secondary

    func testSecondaryHasStrongBorderWhenEnabled() {
        XCTAssertEqual(resolve(.secondary).border, .strong)
        XCTAssertEqual(resolve(.secondary).foreground, .textPrimary)
    }

    func testSecondaryPressedSinksFill() {
        XCTAssertEqual(resolve(.secondary, pressed: true).fill, .surfaceSunken)
    }

    func testSecondaryDisabledDimsTextAndSubtleBorder() {
        let appearance = resolve(.secondary, enabled: false)
        XCTAssertEqual(appearance.foreground, .textDisabled)
        XCTAssertEqual(appearance.border, .subtle)
    }

    // MARK: - Destructive

    func testDestructiveUsesDanger() {
        XCTAssertEqual(resolve(.destructive).fill, .danger)
        XCTAssertEqual(resolve(.destructive).foreground, .onDanger)
    }

    func testDestructivePressed() {
        XCTAssertEqual(resolve(.destructive, pressed: true).fill, .dangerPressed)
    }

    func testDestructiveDisabled() {
        XCTAssertEqual(resolve(.destructive, enabled: false).fill, .dangerDisabled)
    }

    // MARK: - Text

    func testTextVariantIsBorderlessAndClear() {
        XCTAssertEqual(resolve(.text).fill, .clear)
        XCTAssertEqual(resolve(.text).border, .none)
        XCTAssertEqual(resolve(.text).foreground, .brandPrimary)
    }

    func testTextPressedShiftsForeground() {
        XCTAssertEqual(resolve(.text, pressed: true).foreground, .brandPressed)
    }

    func testTextDisabled() {
        XCTAssertEqual(resolve(.text, enabled: false).foreground, .textDisabled)
    }

    // MARK: - Border geometry

    func testBorderWidthIsZeroForNone() {
        XCTAssertEqual(WatakeButtonAppearance.Border.none.width, 0)
        XCTAssertEqual(WatakeButtonAppearance.Border.strong.width, 1)
    }

    // MARK: - Loading blocks interaction

    func testLoadingButtonRejectsTaps() {
        XCTAssertFalse(WatakeButtonStyle.acceptsTaps(isLoading: true))
    }

    func testIdleButtonAcceptsTaps() {
        XCTAssertTrue(WatakeButtonStyle.acceptsTaps(isLoading: false))
    }
}
