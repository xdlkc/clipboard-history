import XCTest
@testable import ClipboardCore

final class RowTextTests: XCTestCase {
    func testTextNewlineAndTabFlattening() {
        XCTAssertEqual(rowText(kind: .text, text: "a\nb").string, "a ⏎ b")
        XCTAssertEqual(rowText(kind: .text, text: "a\tb").string, "a b")
        XCTAssertEqual(rowText(kind: .text, text: "a\n\nb").string, "a ⏎  ⏎ b")
        XCTAssertEqual(rowText(kind: .text, text: "plain").string, "plain")
        XCTAssertEqual(rowText(kind: .text, text: "").string, "")
    }

    func testCRLFAndOtherLineBreaksProduceOneMarkerEach() {
        XCTAssertEqual(rowText(kind: .text, text: "a\r\nb").string, "a ⏎ b")
        XCTAssertEqual(rowText(kind: .text, text: "a\rb").string, "a ⏎ b")
        XCTAssertEqual(rowText(kind: .text, text: "a\u{2028}b\u{2029}c").string, "a ⏎ b ⏎ c")
        XCTAssertEqual(rowText(kind: .text, text: "a\r\n\r\nb").string, "a ⏎  ⏎ b")
    }

    func testRowTextNeverContainsLineBreaksOrTabs() {
        let raw = "第一行\r\n\t第二行\n\r第三\u{2028}行\t😀\n"
        let row = rowText(kind: .text, text: raw).string
        XCTAssertFalse(row.contains(where: { $0.isNewline || $0 == "\t" }))
        XCTAssertEqual(row, "第一行 ⏎  第二行 ⏎  ⏎ 第三 ⏎ 行 😀 ⏎ ")
    }

    func testImageTextIsFlattenedLikeText() {
        XCTAssertEqual(rowText(kind: .image, text: "1024×768").string, "1024×768")
    }

    func testFileRowUsesFileNamesOnly() {
        let paths = "/Users/lkc/Documents/报告 2026.pdf\n/Users/lkc/Pictures/截图 1.png\n/Users/lkc/Projects/demo/"
        let row = rowText(kind: .file, text: paths).string
        XCTAssertEqual(row, "报告 2026.pdf, 截图 1.png, demo")
        XCTAssertFalse(row.contains("/"))
        XCTAssertFalse(row.contains("Users"))
    }

    func testFileRowIgnoresEmptyLinesAndCRLF() {
        XCTAssertEqual(rowText(kind: .file, text: "/a/b.txt\r\n\r\n/c/d.txt\n").string, "b.txt, d.txt")
        XCTAssertEqual(rowText(kind: .file, text: "relative.txt").string, "relative.txt")
        XCTAssertEqual(rowText(kind: .file, text: "/").string, "/")
        XCTAssertEqual(rowText(kind: .file, text: "").string, "")
    }

    func testFileNamesWithTabsAreFlattened() {
        XCTAssertEqual(rowText(kind: .file, text: "/tmp/a\tb.txt").string, "a b.txt")
    }

    func testFileNamesAreSearchableButPathsAreNot() throws {
        let row = rowText(kind: .file, text: "/Users/lkc/Documents/报告.pdf\n/Users/lkc/Pictures/截图.png")
        XCTAssertEqual(row.string, "报告.pdf, 截图.png")

        let m = try XCTUnwrap(Fuzzy.match("截图", in: row))
        let ns = row.string as NSString
        XCTAssertEqual(m.nsRanges().map { ns.substring(with: $0) }, ["截图"])
        XCTAssertNotNil(Fuzzy.match("pdf", in: row))

        XCTAssertNil(Fuzzy.match("Users", in: row))
        XCTAssertNil(Fuzzy.match("Documents", in: row))
        XCTAssertNil(Fuzzy.match("lkc", in: row))
    }
}
