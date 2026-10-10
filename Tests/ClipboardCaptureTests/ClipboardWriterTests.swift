import AppKit
import XCTest
@testable import ClipboardCapture
import ClipboardCore

final class ClipboardWriterTests: XCTestCase {
    private var pb: NSPasteboard!
    private var dir: URL!

    override func setUpWithError() throws {
        pb = NSPasteboard(name: NSPasteboard.Name("ClipboardHistoryWriterTests-\(UUID().uuidString)"))
        pb.clearContents()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("WriterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        pb.releaseGlobally()
        try? FileManager.default.removeItem(at: dir)
    }

    func testWriteTextReturnsChangeCountAndRoundTrips() {
        let before = pb.changeCount
        let count = ClipboardWriter.write(kind: .text, text: "回写\n文本", image: nil, to: pb)
        XCTAssertEqual(count, pb.changeCount)
        XCTAssertNotEqual(count, before)
        XCTAssertEqual(PasteboardReader.read(pb), .text("回写\n文本"))
    }

    func testWriteImageRoundTripsWithSameHash() throws {
        let png = try TestImages.png(width: 40, height: 30)
        XCTAssertNotNil(ClipboardWriter.write(kind: .image, text: "40×30", image: png, to: pb))
        let content = try XCTUnwrap(PasteboardReader.read(pb))
        XCTAssertEqual(content.kind, .image)
        XCTAssertEqual(content.contentHash, ClipboardContent.image(png: png, width: 40, height: 30, thumb: nil).contentHash)
    }

    func testWriteImageWithoutDataWritesNothing() {
        pb.setString("keep", forType: .string)
        XCTAssertNil(ClipboardWriter.write(kind: .image, text: "1×1", image: nil, to: pb))
        XCTAssertEqual(pb.string(forType: .string), "keep")
    }

    func testWriteFilesRoundTrips() throws {
        let paths = [dir.appendingPathComponent("a.txt").path, dir.appendingPathComponent("b 文件.pdf").path]
        XCTAssertNotNil(ClipboardWriter.write(kind: .file, text: paths.joined(separator: "\n"), image: nil, to: pb))
        let content = try XCTUnwrap(PasteboardReader.read(pb))
        XCTAssertEqual(content.kind, .file)
        XCTAssertEqual(content.text, paths.joined(separator: "\n"))
        XCTAssertNil(pb.data(forType: .png))
    }

    func testSingleImageFileAlsoWritesPNG() throws {
        let pic = dir.appendingPathComponent("shot.png")
        try TestImages.png(width: 16, height: 8).write(to: pic)
        XCTAssertNotNil(ClipboardWriter.write(kind: .file, text: pic.path, image: nil, to: pb))
        XCTAssertEqual(PasteboardReader.fileURLs(in: pb).map(\.path), [pic.path])
        let png = try XCTUnwrap(pb.data(forType: .png))
        let size = try XCTUnwrap(ImageUtil.pixelSize(of: png))
        XCTAssertEqual(size.width, 16)
        XCTAssertEqual(size.height, 8)
        XCTAssertEqual(PasteboardReader.read(pb)?.kind, .file)
    }

    func testMultipleImageFilesDoNotWritePNG() throws {
        let a = dir.appendingPathComponent("a.png")
        let b = dir.appendingPathComponent("b.png")
        try TestImages.png().write(to: a)
        try TestImages.png().write(to: b)
        XCTAssertNotNil(ClipboardWriter.write(kind: .file, text: "\(a.path)\n\(b.path)", image: nil, to: pb))
        XCTAssertNil(pb.data(forType: .png))
    }
}
