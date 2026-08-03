import XCTest
import AppKit
@testable import ShotEditor

final class RendererTests: XCTestCase {

    private func doc(_ w: Int = 80, _ h: Int = 40, fill: NSColor = .white) -> EditorDocument {
        EditorDocument(image: TestSupport.makeImage(w, h, fill: fill))
    }

    func testFlattenPreservesSize() {
        let d = doc(80, 40)
        let flat = Renderer.flatten(d)
        XCTAssertEqual(flat.pixelSizeOrDefault, CGSize(width: 80, height: 40))
    }

    func testFlattenDrawsAnnotation() {
        let d = doc(100, 100, fill: .white)
        let rect = ShapeAnnotation(kind: .rect, p0: CGPoint(x: 20, y: 20), p1: CGPoint(x: 80, y: 80))
        rect.color = .red; rect.filled = true
        d.add(rect)
        let flat = Renderer.flatten(d)
        // center should be reddish now
        let c = TestSupport.pixel(flat, 50, 50)
        XCTAssertGreaterThan(c.redComponent, 0.6)
        XCTAssertLessThan(c.greenComponent, 0.4)
    }

    func testCropSize() {
        let d = doc(100, 100)
        let flat = Renderer.flatten(d)
        let cropped = Renderer.crop(flat, to: CGRect(x: 10, y: 10, width: 40, height: 30))
        XCTAssertEqual(cropped.pixelSizeOrDefault, CGSize(width: 40, height: 30))
    }

    func testRotateSwapsDimensions() {
        let d = doc(80, 40)
        let r = Renderer.rotated(d, clockwise: true)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.pixelSizeOrDefault, CGSize(width: 40, height: 80))
    }

    func testFlipKeepsDimensions() {
        let d = doc(80, 40)
        let f = Renderer.flipped(d, horizontal: true)
        XCTAssertEqual(f!.pixelSizeOrDefault, CGSize(width: 80, height: 40))
    }

    func testScalePreservesAspect() {
        let d = doc(80, 40)
        let s = Renderer.scaled(d, to: 40)
        XCTAssertNotNil(s)
        let sz = s!.pixelSizeOrDefault
        XCTAssertEqual(sz.width, 40, accuracy: 1)
        XCTAssertEqual(sz.height, 20, accuracy: 1)
    }

    func testBackdropExportSize() {
        let d = doc(80, 40)
        XCTAssertEqual(Renderer.flattenForExport(d).pixelSizeOrDefault, CGSize(width: 80, height: 40))
        d.backdrop.enabled = true
        d.backdrop.padding = 25
        XCTAssertEqual(Renderer.flattenForExport(d).pixelSizeOrDefault,
                       CGSize(width: 130, height: 90))  // +2*25 each side
    }

    func testSolidRedactionActuallyHides() {
        let d = doc(100, 60, fill: .white)
        // Cover the whole image with a solid redaction.
        let blur = BlurAnnotation(rect: CGRect(x: 0, y: 0, width: 100, height: 60), style: .solid)
        d.add(blur)
        let flat = Renderer.flatten(d)
        let c = TestSupport.pixel(flat, 50, 30)
        XCTAssertLessThan(TestSupport.luminance(c), 0.25, "solid redaction must be dark/opaque")
    }

    func testPixelateObscuresContent() {
        // A thin black stripe on white must be destroyed (diluted) by the big
        // pixelation blocks — proving fine detail like text can't survive.
        let img = TestSupport.makeImage(160, 60, fill: .white)
        let d = EditorDocument(image: img)
        let stripe = ShapeAnnotation(kind: .rect, p0: CGPoint(x: 78, y: 0), p1: CGPoint(x: 82, y: 60))
        stripe.color = .black; stripe.filled = true
        d.add(stripe)

        // Sanity: without redaction the stripe centre is nearly black.
        XCTAssertLessThan(TestSupport.luminance(TestSupport.pixel(Renderer.flatten(d), 80, 30)), 0.2)

        let px = BlurAnnotation(rect: CGRect(x: 20, y: 0, width: 120, height: 60), style: .pixelate)
        px.amount = 0.8
        d.add(px)
        let after = TestSupport.luminance(TestSupport.pixel(Renderer.flatten(d), 80, 30))
        XCTAssertGreaterThan(after, 0.4, "thin dark detail must be diluted away by pixelation")
    }

    func testPixelateAndBlurRunWithoutCrash() {
        for style in [BlurStyle.pixelate, .blur] {
            let d = doc(120, 80, fill: .white)
            let b = BlurAnnotation(rect: CGRect(x: 10, y: 10, width: 80, height: 50), style: style)
            b.amount = 0.8
            d.add(b)
            XCTAssertEqual(Renderer.flatten(d).pixelSizeOrDefault, CGSize(width: 120, height: 80))
        }
    }
}
