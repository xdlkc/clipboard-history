import XCTest
@testable import ClipboardCore

/// 坑 1 回归:搜索高亮越界崩溃。匹配与高亮必须都在 rowText 上进行,NSRange 转换不得越界。
final class Pitfall1RegressionTests: XCTestCase {
    private static let highlightKey = NSAttributedString.Key("highlight")

    /// 模拟列表行高亮:在 rowText 上建 NSMutableAttributedString 并对每个 NSRange 加属性(越界会抛异常崩溃)。
    /// 断言每个区间都在界内,且高亮子串拼起来等于 query(忽略大小写)。
    @discardableResult
    private func assertHighlightSafe(_ query: String, in row: RowText, file: StaticString = #filePath, line: UInt = #line) throws -> [String] {
        let m = try XCTUnwrap(Fuzzy.match(query, in: row), "「\(query)」应命中", file: file, line: line)
        let attributed = NSMutableAttributedString(string: row.string)
        let length = attributed.length
        let ns = row.string as NSString
        var pieces: [String] = []
        for r in m.nsRanges(clampedTo: length) {
            XCTAssertGreaterThanOrEqual(r.location, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(NSMaxRange(r), length, file: file, line: line)
            attributed.addAttribute(Self.highlightKey, value: true, range: r)
            pieces.append(ns.substring(with: r))
        }
        XCTAssertEqual(pieces.joined().lowercased(), query.lowercased(), file: file, line: line)
        return pieces
    }

    func testMultilineTextWithTabsMatchesOnRowText() throws {
        let raw = "func main() {\n\tlet value = 42\n\tprint(value)\n}"
        let row = rowText(kind: .text, text: raw)
        XCTAssertEqual(row.string, "func main() { ⏎  let value = 42 ⏎  print(value) ⏎ }")
        XCTAssertEqual(try assertHighlightSafe("print", in: row), ["print"])
        try assertHighlightSafe("value42", in: row)
        try assertHighlightSafe("}", in: row)
    }

    func testCRLFTextMatchesAndHighlightsInBounds() throws {
        let row = rowText(kind: .text, text: "line one\r\nline two\r\nend")
        XCTAssertEqual(row.string, "line one ⏎ line two ⏎ end")
        XCTAssertEqual(try assertHighlightSafe("two", in: row), ["two"])
        XCTAssertEqual(try assertHighlightSafe("end", in: row), ["end"])
    }

    func testChineseAndEmojiHighlight() throws {
        let row = rowText(kind: .text, text: "今天天气😀很好\n\t明天🌧️下雨")
        XCTAssertEqual(row.string, "今天天气😀很好 ⏎  明天🌧️下雨")
        XCTAssertEqual(try assertHighlightSafe("天气😀", in: row), ["天气😀"])
        XCTAssertEqual(try assertHighlightSafe("🌧️下雨", in: row), ["🌧️下雨"])
        XCTAssertEqual(try assertHighlightSafe("今好明雨", in: row), ["今", "好", "明", "雨"])
    }

    func testMultiScalarEmojiIsMatchedAsWholeCharacter() throws {
        let family = "👨‍👩‍👧‍👦"
        let row = rowText(kind: .text, text: "家庭 \(family)\n国旗 🇨🇳 点赞 👍🏽 é")
        XCTAssertEqual(try assertHighlightSafe(family, in: row), [family])
        XCTAssertEqual(try assertHighlightSafe("🇨🇳", in: row), ["🇨🇳"])
        XCTAssertEqual(try assertHighlightSafe("👍🏽", in: row), ["👍🏽"])

        let m = try XCTUnwrap(Fuzzy.match(family, in: row))
        XCTAssertEqual(m.nsRanges().first?.length, (family as NSString).length)

        // 只输入 ZWJ 序列中的一个分量不会命中半个字符簇,避免高亮切开 emoji
        XCTAssertNil(Fuzzy.match("👨", in: row))
        XCTAssertNil(Fuzzy.match("🇨", in: row))
    }

    func testDecomposedAccentMatchesPrecomposedQuery() throws {
        let row = rowText(kind: .text, text: "cafe\u{301}\nmenu")
        let pieces = try assertHighlightSafe("caf\u{e9}", in: row)
        XCTAssertEqual(pieces, ["cafe\u{301}"])
    }

    func testKeywordInMultilineTerminalOutput() throws {
        let raw = """
        $ swift build -c release --arch arm64\r
        Building for production...\r
        [1/4] Compiling ClipboardCore Fuzzy.swift\r
        /Users/lkc/clipboard-history/Sources/ClipboardHistory/PanelController.swift:42:17:\terror: cannot find 'foo' in scope\r
        \t\tfoo()\r
        \t\t^~~\r
        ❌ Build failed (3.21s) 🚨\r
        """
        let row = rowText(kind: .text, text: raw)
        XCTAssertFalse(row.string.contains(where: { $0.isNewline || $0 == "\t" }))

        XCTAssertEqual(try assertHighlightSafe("error", in: row), ["error"])
        XCTAssertEqual(try assertHighlightSafe("Build failed", in: row), ["Build failed"])
        XCTAssertEqual(try assertHighlightSafe("🚨", in: row), ["🚨"])
        try assertHighlightSafe("swift:42", in: row)
        try assertHighlightSafe("foo()", in: row)
        try assertHighlightSafe("arm64production", in: row)
    }

    func testEveryRangeConvertsSafelyAcrossCorpus() throws {
        let corpus = [
            "a\tb\nc\r\nd\re",
            "中文\t混排 English\n第二行😀😀\r\n",
            "👨‍👩‍👧‍👦\t👍🏽\n🇨🇳🇯🇵\r\nzwj",
            "\n\n\n\t\t\t",
            "trailing newline\n",
            "\u{2028}sep\u{2029}x\u{85}y",
            "e\u{301}\u{301}\tcombining",
        ]
        for raw in corpus {
            let row = rowText(kind: .text, text: raw)
            let chars = Array(row.string)
            // 用 rowText 中的每个单字符和每个相邻字符对作为 query
            var queries = chars.map { String($0) }
            if chars.count > 1 {
                for i in 0..<(chars.count - 1) { queries.append(String(chars[i]) + String(chars[i + 1])) }
            }
            queries.append(row.string)
            for q in queries where !q.isEmpty {
                try assertHighlightSafe(q, in: row)
            }
        }
    }

    func testHighlightHelperDropsOutOfBoundsAndClamps() throws {
        let long = rowText(kind: .text, text: "0123456789\n😀😀😀")
        let short = rowText(kind: .text, text: "012")
        let m = try XCTUnwrap(Fuzzy.match("9😀", in: long))

        // 别的字符串上的区间(越界)被丢弃,而不是崩溃
        XCTAssertEqual(Highlight.nsRanges(m.ranges, in: short), [])

        // 实际显示的字符串比 rowText 短时(例如被截断),裁剪到给定长度
        let clamped = m.nsRanges(clampedTo: 10)
        XCTAssertTrue(clamped.allSatisfy { NSMaxRange($0) <= 10 })
        XCTAssertEqual(clamped, [NSRange(location: 9, length: 1)])
        XCTAssertEqual(m.nsRanges(clampedTo: 0), [])
        XCTAssertEqual(m.nsRanges(clampedTo: -5), [])
        XCTAssertEqual(m.nsRanges(clampedTo: 10_000), m.nsRanges())
    }

    func testRawTextRangesWouldDifferFromRowText() throws {
        // 说明为何必须在 rowText 上匹配:展平后 UTF-16 偏移整体右移,原文上的区间放到显示串上会错位
        let raw = "x\ny\nkeyword"
        let row = rowText(kind: .text, text: raw)
        let m = try XCTUnwrap(Fuzzy.match("keyword", in: row))
        let rowLocation = try XCTUnwrap(m.nsRanges().first).location
        let rawLocation = (raw as NSString).range(of: "keyword").location
        XCTAssertNotEqual(rowLocation, rawLocation)
        XCTAssertEqual((row.string as NSString).substring(with: try XCTUnwrap(m.nsRanges().first)), "keyword")
    }
}
