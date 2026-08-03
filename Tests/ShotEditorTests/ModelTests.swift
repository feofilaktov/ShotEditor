import XCTest
import AppKit
@testable import ShotEditor

final class ModelTests: XCTestCase {

    func testDocumentImageSizeNoDoubling() {
        let d = EditorDocument(image: TestSupport.makeImage(64, 48))
        XCTAssertEqual(d.imageSize, CGSize(width: 64, height: 48))
    }

    func testHitTestReturnsTopmost() {
        let d = EditorDocument(image: TestSupport.makeImage(100, 100))
        let a = ShapeAnnotation(kind: .rect, p0: .zero, p1: CGPoint(x: 100, y: 100)); a.filled = true
        let b = ShapeAnnotation(kind: .rect, p0: .zero, p1: CGPoint(x: 100, y: 100)); b.filled = true
        d.add(a); d.add(b)
        XCTAssertTrue(d.hitTest(CGPoint(x: 50, y: 50), tolerance: 2) === b, "last added is topmost")
    }

    func testRemove() {
        let d = EditorDocument(image: TestSupport.makeImage(10, 10))
        let a = PenAnnotation(points: [.zero])
        d.add(a)
        XCTAssertEqual(d.annotations.count, 1)
        d.remove(a)
        XCTAssertEqual(d.annotations.count, 0)
    }

    func testToolSettingsDefaults() {
        let s = ToolSettings()
        XCTAssertEqual(s.blurStyle, .pixelate)
        XCTAssertEqual(s.nextNumber, 1)
        XCTAssertFalse(s.dashed)
        XCTAssertEqual(s.lineWidth, 4)
    }

    func testToolKindShortcutsUnique() {
        let shortcuts = ToolKind.allCases.map { $0.shortcut }
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count, "tool shortcuts must be unique")
    }

    func testBackdropTotalSizeAndOrigin() {
        var b = Backdrop()
        XCTAssertEqual(b.totalSize(for: CGSize(width: 100, height: 50)), CGSize(width: 100, height: 50))
        b.enabled = true; b.padding = 30
        XCTAssertEqual(b.totalSize(for: CGSize(width: 100, height: 50)), CGSize(width: 160, height: 110))
        XCTAssertEqual(b.imageOrigin(), CGPoint(x: 30, y: 30))
    }

    func testBackdropStyleColors() {
        XCTAssertEqual(Backdrop.Style.solid.colors.count, 1)
        XCTAssertEqual(Backdrop.Style.oceanGradient.colors.count, 2)
    }

    func testRecentScreenshotsRoundTrip() {
        RecentScreenshots.clear()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rtest-\(UUID().uuidString).png")
        try? Data([0x1]).write(to: tmp)
        RecentScreenshots.add(tmp)
        XCTAssertTrue(RecentScreenshots.urls().contains(tmp))
        try? FileManager.default.removeItem(at: tmp)
        XCTAssertFalse(RecentScreenshots.urls().contains(tmp), "missing files are filtered out")
        RecentScreenshots.clear()
    }
}
