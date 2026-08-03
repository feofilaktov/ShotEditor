import XCTest
import AppKit
@testable import ShotEditor

final class HandleTests: XCTestCase {

    func testRectHandlesOrderAndCount() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 50)
        let h = Annotation.rectHandles(r)
        XCTAssertEqual(h.count, 8)
        XCTAssertEqual(h[0], CGPoint(x: 0, y: 0))     // bl
        XCTAssertEqual(h[3], CGPoint(x: 100, y: 50))  // tr
        XCTAssertEqual(h[5], CGPoint(x: 100, y: 25))  // right mid
    }

    func testResizedRectCorner() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 50)
        // drag top-right (index 3) to (120, 80)
        let nr = Annotation.resizedRect(r, handle: 3, to: CGPoint(x: 120, y: 80))
        XCTAssertEqual(nr, CGRect(x: 0, y: 0, width: 120, height: 80))
    }

    func testResizedRectMinSize() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 50)
        let nr = Annotation.resizedRect(r, handle: 5, to: CGPoint(x: 1, y: 0), minSize: 8)
        XCTAssertGreaterThanOrEqual(nr.width, 8)
    }

    func testArrowHandles() {
        let a = ArrowAnnotation(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10), style: .line)
        XCTAssertEqual(a.resizeHandles(), [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        a.moveHandle(1, to: CGPoint(x: 20, y: 20))
        XCTAssertEqual(a.end, CGPoint(x: 20, y: 20))
    }

    func testShapeHandlesResize() {
        let s = ShapeAnnotation(kind: .rect, p0: .zero, p1: CGPoint(x: 40, y: 40))
        XCTAssertEqual(s.resizeHandles().count, 8)
        s.moveHandle(3, to: CGPoint(x: 60, y: 80)) // top-right
        XCTAssertEqual(s.rect, CGRect(x: 0, y: 0, width: 60, height: 80))
    }

    func testShapeLineHandles() {
        let s = ShapeAnnotation(kind: .line, p0: .zero, p1: CGPoint(x: 10, y: 0))
        XCTAssertEqual(s.resizeHandles().count, 2)
        s.moveHandle(0, to: CGPoint(x: -5, y: -5))
        XCTAssertEqual(s.p0, CGPoint(x: -5, y: -5))
    }

    func testNumberResizeHandleSetsDiameter() {
        let n = NumberAnnotation(center: CGPoint(x: 50, y: 50), number: 1, diameter: 40)
        n.moveHandle(3, to: CGPoint(x: 80, y: 50)) // 30 from center → diameter 60
        XCTAssertEqual(n.diameter, 60, accuracy: 0.001)
    }

    func testCalloutHandlesIncludeTail() {
        let c = CalloutAnnotation(rect: CGRect(x: 0, y: 0, width: 100, height: 40),
                                  tailTip: CGPoint(x: 30, y: -20), font: .systemFont(ofSize: 14))
        XCTAssertEqual(c.resizeHandles().count, 9)
        c.moveHandle(8, to: CGPoint(x: 5, y: -40))
        XCTAssertEqual(c.tailTip, CGPoint(x: 5, y: -40))
    }
}
