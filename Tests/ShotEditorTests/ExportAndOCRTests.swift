import XCTest
import AppKit
import Vision
@testable import ShotEditor

final class ExportAndOCRTests: XCTestCase {

    func testPNGAndJPEGData() {
        let img = TestSupport.makeImage(40, 30, fill: .blue)
        let png = ImageExport.data(from: img, format: .png)
        let jpg = ImageExport.data(from: img, format: .jpeg)
        XCTAssertNotNil(png)
        XCTAssertNotNil(jpg)
        // PNG round-trips to the same pixel size.
        let back = NSImage(data: png!)!
        XCTAssertEqual(back.pixelSizeOrDefault, CGSize(width: 40, height: 30))
    }

    func testPNGSignature() {
        let img = TestSupport.makeImage(8, 8)
        let png = ImageExport.data(from: img, format: .png)!
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47]) // \x89PNG
    }

    func testCopyToPasteboardSetsImage() {
        let img = TestSupport.makeImage(20, 20, fill: .green)
        ImageExport.copyToPasteboard(img)
        let types = NSPasteboard.general.types ?? []
        XCTAssertTrue(types.contains(.png) || types.contains(.tiff),
                      "clipboard should carry image data")
    }

    func testOCRRecognizesText() {
        let img = TestSupport.makeImage(360, 90, fill: .white, text: "HELLO")
        let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        let lines = (request.results as? [VNRecognizedTextObservation])?
            .compactMap { $0.topCandidates(1).first?.string } ?? []
        XCTAssertTrue(lines.joined(separator: " ").uppercased().contains("HELLO"),
                      "OCR should read HELLO, got \(lines)")
    }
}
