import AppKit
import XCTest
@testable import ClipboardCapture
import ClipboardCore

/// 在独立的命名剪贴板上运行,不触碰系统剪贴板。
final class PasteboardReaderTests: XCTestCase {
    private var pb: NSPasteboard!
    private var dir: URL!

    override func setUpWithError() throws {
        pb = NSPasteboard(name: NSPasteboard.Name("ClipboardHistoryTests-\(UUID().uuidString)"))
        pb.clearContents()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        pb.releaseGlobally()
        try? FileManager.default.removeItem(at: dir)
    }

    func testEmptyPasteboardReturnsNil() {
        XCTAssertNil(PasteboardReader.read(pb))
    }

    func testSkipsConcealedAndTransient() {
        for marker in PasteboardReader.skippedTypes {
            pb.clearContents()
            pb.declareTypes([.string, marker], owner: nil)
            pb.setString("secret", forType: .string)
            pb.setData(Data(), forType: marker)
            XCTAssertNil(PasteboardReader.read(pb), marker.rawValue)
        }
    }

    func testPlainText() {
        pb.setString("第一行\n\tsecond", forType: .string)
        XCTAssertEqual(PasteboardReader.read(pb), .text("第一行\n\tsecond"))
    }

    func testRTFConvertedToPlainText() throws {
        let attributed = NSAttributedString(string: "富文本 RTF", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        let rtf = try XCTUnwrap(attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]))
        pb.setData(rtf, forType: .rtf)
        XCTAssertEqual(PasteboardReader.read(pb), .text("富文本 RTF"))
    }

    func testTextBeatsRTFAndImages() throws {
        pb.declareTypes([.string, .png], owner: nil)
        pb.setString("plain wins", forType: .string)
        pb.setData(try TestImages.png(), forType: .png)
        XCTAssertEqual(PasteboardReader.read(pb)?.kind, .text)
    }

    func testFileURLsBeatTextAndUsePaths() throws {
        let a = dir.appendingPathComponent("报告 1.txt")
        let b = dir.appendingPathComponent("notes.md")
        pb.writeObjects([a, b] as [NSURL])
        let content = try XCTUnwrap(PasteboardReader.read(pb))
        XCTAssertEqual(content.kind, .file)
        XCTAssertEqual(content.text, "\(a.path)\n\(b.path)")
        XCTAssertNil(content.thumb)
        XCTAssertEqual(rowText(kind: content.kind, text: content.text).string, "报告 1.txt, notes.md")
    }

    func testNonFileURLIsNotTreatedAsFile() {
        pb.declareTypes([.URL, .string], owner: nil)
        pb.setString("https://example.com/a", forType: .URL)
        pb.setString("https://example.com/a", forType: .string)
        XCTAssertEqual(PasteboardReader.read(pb), .text("https://example.com/a"))
    }

    func testFileThumbnailFromFirstImageFileOnDisk() throws {
        let txt = dir.appendingPathComponent("a.txt")
        let pic = dir.appendingPathComponent("pic.png")
        try Data("x".utf8).write(to: txt)
        try TestImages.png(width: 200, height: 100).write(to: pic)
        pb.writeObjects([txt, pic] as [NSURL])

        let content = try XCTUnwrap(PasteboardReader.read(pb))
        XCTAssertEqual(content.kind, .file)
        let thumb = try XCTUnwrap(content.thumb)
        let size = try XCTUnwrap(ImageUtil.pixelSize(of: thumb))
        XCTAssertEqual(size.width, 64)
        XCTAssertEqual(size.height, 32)
    }

    func testFileThumbnailPrefersPasteboardPNG() throws {
        let missing = dir.appendingPathComponent("not-on-disk.jpg")
        pb.writeObjects([missing] as [NSURL])
        pb.setData(try TestImages.png(width: 50, height: 100), forType: .png)

        let content = try XCTUnwrap(PasteboardReader.read(pb))
        XCTAssertEqual(content.kind, .file)
        let size = try XCTUnwrap(ImageUtil.pixelSize(of: try XCTUnwrap(content.thumb)))
        XCTAssertEqual(size.width, 32)
        XCTAssertEqual(size.height, 64)
    }

    func testPNGImage() throws {
        let png = try TestImages.png(width: 200, height: 100)
        pb.setData(png, forType: .png)
        let content = try XCTUnwrap(PasteboardReader.read(pb))
        XCTAssertEqual(content.kind, .image)
        XCTAssertEqual(content.text, "200×100")
        XCTAssertEqual(content.image, png)
        XCTAssertEqual(content.contentHash, ContentHash.sha256(kind: .image, png))
        let thumb = try XCTUnwrap(ImageUtil.pixelSize(of: try XCTUnwrap(content.thumb)))
        XCTAssertEqual(thumb.width, 64)
        XCTAssertEqual(thumb.height, 32)
    }

    func testTIFFConvertedToPNG() throws {
        pb.setData(try TestImages.tiff(width: 30, height: 40), forType: .tiff)
        let content = try XCTUnwrap(PasteboardReader.read(pb))
        XCTAssertEqual(content.kind, .image)
        XCTAssertEqual(content.text, "30×40")
        let image = try XCTUnwrap(content.image)
        XCTAssertEqual(Array(image.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let thumb = try XCTUnwrap(ImageUtil.pixelSize(of: try XCTUnwrap(content.thumb)))
        XCTAssertEqual(thumb.width, 30, "小图不放大")
        XCTAssertEqual(thumb.height, 40)
    }

    func testPNGBeatsTIFF() throws {
        let png = try TestImages.png(width: 10, height: 10)
        pb.declareTypes([.tiff, .png], owner: nil)
        pb.setData(try TestImages.tiff(width: 30, height: 40), forType: .tiff)
        pb.setData(png, forType: .png)
        XCTAssertEqual(PasteboardReader.read(pb)?.image, png)
    }

    func testOversizeImageSkipped() throws {
        let png = try TestImages.png(width: 200, height: 100)
        pb.setData(png, forType: .png)
        XCTAssertNil(PasteboardReader.read(pb, maxImageBytes: png.count - 1))
        XCTAssertNotNil(PasteboardReader.read(pb, maxImageBytes: png.count))
        XCTAssertEqual(PasteboardReader.maxImageBytes, 20 * 1024 * 1024)
    }

    func testInvalidImageDataSkipped() {
        pb.setData(Data([1, 2, 3]), forType: .png)
        XCTAssertNil(PasteboardReader.read(pb))
    }

    func testPNGFromFileUsesNSImageRoute() throws {
        let pic = dir.appendingPathComponent("p.png")
        try TestImages.png(width: 12, height: 7).write(to: pic)
        let png = try XCTUnwrap(ImageUtil.pngData(fromFile: pic.path))
        let size = try XCTUnwrap(ImageUtil.pixelSize(of: png))
        XCTAssertEqual(size.width, 12)
        XCTAssertEqual(size.height, 7)
        XCTAssertNil(ImageUtil.pngData(fromFile: dir.appendingPathComponent("missing.png").path))
    }
}

enum TestImages {
    static func rep(width: Int, height: Int) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<width {
            for y in 0..<height {
                rep.setColor(NSColor(deviceRed: CGFloat(x) / CGFloat(width), green: CGFloat(y) / CGFloat(height),
                                     blue: 0.5, alpha: 1), atX: x, y: y)
            }
        }
        return rep
    }

    static func png(width: Int = 20, height: Int = 20) throws -> Data {
        try XCTUnwrap(rep(width: width, height: height).representation(using: .png, properties: [:]))
    }

    static func tiff(width: Int, height: Int) throws -> Data {
        try XCTUnwrap(rep(width: width, height: height).tiffRepresentation)
    }
}
