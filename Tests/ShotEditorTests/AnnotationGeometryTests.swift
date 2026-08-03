import XCTest
import AppKit
@testable import ShotEditor

final class AnnotationGeometryTests: XCTestCase {

    func testDistanceToSegment() {
        let d = Annotation.distance(point: CGPoint(x: 5, y: 5),
                                    toSegment: CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0))
        XCTAssertEqual(d, 5, accuracy: 0.001)
        let end = Annotation.distance(point: CGPoint(x: 15, y: 0),
                                      toSegment: CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0))
        XCTAssertEqual(end, 5, accuracy: 0.001)  // clamps to endpoint
    }

    func testArrowGeometry() {
        let a = ArrowAnnotation(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .filled)
        a.lineWidth = 4
        XCTAssertEqual(a.bounds.width, 100, accuracy: 0.001)
        XCTAssertTrue(a.hitTest(CGPoint(x: 50, y: 1), tolerance: 6))
        XCTAssertFalse(a.hitTest(CGPoint(x: 50, y: 40), tolerance: 6))
        a.translate(by: CGVector(dx: 10, dy: 5))
        XCTAssertEqual(a.start, CGPoint(x: 10, y: 5))
        XCTAssertEqual(a.end, CGPoint(x: 110, y: 5))
    }

    func testShapeRectAndHitTest() {
        let s = ShapeAnnotation(kind: .rect, p0: CGPoint(x: 10, y: 10), p1: CGPoint(x: 50, y: 30))
        XCTAssertEqual(s.rect, CGRect(x: 10, y: 10, width: 40, height: 20))
        s.filled = true
        XCTAssertTrue(s.hitTest(CGPoint(x: 30, y: 20), tolerance: 2))
        s.filled = false
        // stroke-only: center should miss, edge should hit
        XCTAssertFalse(s.hitTest(CGPoint(x: 30, y: 20), tolerance: 2))
        XCTAssertTrue(s.hitTest(CGPoint(x: 10, y: 20), tolerance: 3))
    }

    func testPenBoundsAndHit() {
        let p = PenAnnotation(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 0)])
        p.lineWidth = 4
        XCTAssertTrue(p.hitTest(CGPoint(x: 10, y: 10), tolerance: 4))
        XCTAssertFalse(p.hitTest(CGPoint(x: 100, y: 100), tolerance: 4))
    }

    func testNumberCircleHit() {
        let n = NumberAnnotation(center: CGPoint(x: 50, y: 50), number: 1, diameter: 40)
        XCTAssertTrue(n.hitTest(CGPoint(x: 50, y: 50), tolerance: 0))
        XCTAssertTrue(n.hitTest(CGPoint(x: 69, y: 50), tolerance: 0))     // within radius 20
        XCTAssertFalse(n.hitTest(CGPoint(x: 90, y: 50), tolerance: 0))
    }

    func testTextBoundsNonEmpty() {
        let t = TextAnnotation(origin: CGPoint(x: 0, y: 100), string: "Hello",
                               font: .systemFont(ofSize: 20))
        XCTAssertGreaterThan(t.bounds.width, 0)
        XCTAssertGreaterThan(t.bounds.height, 0)
    }

    func testCalloutAutoContrast() {
        let c = CalloutAnnotation(rect: CGRect(x: 0, y: 0, width: 100, height: 40),
                                  tailTip: .zero, font: .systemFont(ofSize: 14))
        c.color = .black
        XCTAssertEqual(TestSupport.luminance(c.autoTextColor), TestSupport.luminance(.white), accuracy: 0.05)
        c.color = .white
        XCTAssertLessThan(TestSupport.luminance(c.autoTextColor), 0.3) // dark text on light bubble
    }

    func testCloneIsIndependent() {
        let s = ShapeAnnotation(kind: .rect, p0: .zero, p1: CGPoint(x: 10, y: 10))
        s.color = .red
        let c = s.clone() as! ShapeAnnotation
        c.translate(by: CGVector(dx: 100, dy: 0))
        XCTAssertEqual(s.p0, .zero, "mutating clone must not affect original")
        XCTAssertEqual(c.p0, CGPoint(x: 100, y: 0))
    }
}
