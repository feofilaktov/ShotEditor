import XCTest
import AppKit
@testable import ShotEditor

final class SmokeTests: XCTestCase {
    func testPaletteHasEightSwatches() {
        XCTAssertEqual(Palette.swatches.count, 8)
        XCTAssertEqual(Palette.transparent.name, "transparent")
    }
}
