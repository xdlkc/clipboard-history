import XCTest
@testable import ClipboardCore

final class ContentHashTests: XCTestCase {
    func testKnownVectors() {
        // sha256(b"\x00hello") / sha256(b"\x02/tmp/a.txt")
        XCTAssertEqual(ClipboardContent.text("hello").contentHash,
                       "8a2a5c9b768827de5a9552c38a044c66959c68f6d2f21b5260af54d2f87db827")
        XCTAssertEqual(ClipboardContent.files(paths: ["/tmp/a.txt"], thumb: nil).contentHash,
                       "8137f0c5834ddab48443812752f24ec99dda4f068811bf2a0ab86667ebfc4fa3")
    }

    func testStableAndContentSensitive() {
        XCTAssertEqual(ClipboardContent.text("中文😀").contentHash, ClipboardContent.text("中文😀").contentHash)
        XCTAssertNotEqual(ClipboardContent.text("a").contentHash, ClipboardContent.text("b").contentHash)
        XCTAssertEqual(ClipboardContent.text("x").contentHash.count, 64)
    }

    func testKindParticipatesInHash() {
        let bytes = Data("/tmp/a.txt".utf8)
        XCTAssertNotEqual(ClipboardContent.text("/tmp/a.txt").contentHash,
                          ClipboardContent.files(paths: ["/tmp/a.txt"], thumb: nil).contentHash)
        XCTAssertNotEqual(ContentHash.sha256(kind: .image, bytes), ContentHash.sha256(kind: .text, bytes))
    }

    func testImageHashIgnoresThumbnailAndDimensionsText() {
        let png = Data([1, 2, 3])
        let a = ClipboardContent.image(png: png, width: 1, height: 1, thumb: Data([9]))
        let b = ClipboardContent.image(png: png, width: 1, height: 1, thumb: nil)
        XCTAssertEqual(a.contentHash, b.contentHash)
        XCTAssertEqual(a.contentHash, ContentHash.sha256(kind: .image, png))
    }
}
