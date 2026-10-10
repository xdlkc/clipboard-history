import XCTest
@testable import ClipboardCore

final class FuzzyTests: XCTestCase {
    private func text(_ s: String) -> RowText { rowText(kind: .text, text: s) }

    private func highlighted(_ m: FuzzyMatch) -> [String] {
        let ns = m.target.string as NSString
        return m.nsRanges().map { ns.substring(with: $0) }
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(Fuzzy.match("xyz", in: text("hello world")))
        XCTAssertNil(Fuzzy.match("ba", in: text("ab")), "顺序不对不算子序列")
        XCTAssertNil(Fuzzy.match("a", in: text("")))
    }

    func testEmptyQueryMatchesWithZeroScore() {
        let m = Fuzzy.match("", in: text("anything"))
        XCTAssertEqual(m?.score, 0)
        XCTAssertEqual(m?.ranges.isEmpty, true)
    }

    func testScoringBaseConsecutiveBoundary() throws {
        // "abc" 串首:a=4+4(边界), b=4+8(连续), c=4+8 → 32
        XCTAssertEqual(try XCTUnwrap(Fuzzy.match("abc", in: text("abc"))).score, 32)
        // "xaxbxc":三个都不连续不在边界 → 12
        XCTAssertEqual(try XCTUnwrap(Fuzzy.match("abc", in: text("xaxbxc"))).score, 12)
        // "x a-b" 中 a 在空格后、b 在 '-' 后 → (4+4)+(4+4) = 16
        XCTAssertEqual(try XCTUnwrap(Fuzzy.match("ab", in: text("x a-b"))).score, 16)
        for sep in " /_-.,:;()[]{}\"'" {
            let m = try XCTUnwrap(Fuzzy.match("b", in: text("a\(sep)b")))
            XCTAssertEqual(m.score, 8, "边界字符 \(sep)")
        }
        XCTAssertEqual(try XCTUnwrap(Fuzzy.match("b", in: text("ab"))).score, 4)
    }

    func testCaseInsensitive() throws {
        let m = try XCTUnwrap(Fuzzy.match("HeLLo", in: text("hello")))
        XCTAssertEqual(m.score, 4 + 4 + 4 * 12)
        XCTAssertNotNil(Fuzzy.match("ÄB", in: text("äb")))
    }

    func testRangesAreMergedAndHighlightCorrectSubstrings() throws {
        let m = try XCTUnwrap(Fuzzy.match("hewo", in: text("hello world")))
        XCTAssertEqual(highlighted(m), ["he", "wo"])
        XCTAssertEqual(m.nsRanges(), [NSRange(location: 0, length: 2), NSRange(location: 6, length: 2)])
    }

    func testRankOrdersByScoreDescendingAndKeepsOrderOnTies() {
        let items = ["xcxlxixp", "clip", "a clip", "nothing", "clip"]
        let ranked = Fuzzy.rank("clip", items) { rowText(kind: .text, text: $0) }
        XCTAssertEqual(ranked.map(\.item), ["clip", "a clip", "clip", "xcxlxixp"])
        XCTAssertEqual(ranked.map(\.match.score), [44, 44, 44, 16])
        XCTAssertEqual(Fuzzy.rank("", items) { rowText(kind: .text, text: $0) }.map(\.item), items)
    }

    func testPathologicalLongInputFinishesAndStillMatches() throws {
        let row = text(String(repeating: "e", count: 100_000) + "rror")
        let start = Date()
        let m = try XCTUnwrap(Fuzzy.match("error", in: row))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        // 预算耗尽后保留已找到的最佳结果,高亮可能不是最优但必然合法
        XCTAssertEqual(highlighted(m).joined(), "error")
    }

    func testRankPrefersConsecutiveAndBoundaryMatches() {
        let items = ["c_l_i_p", "xclipx", "cxlxixp"]
        let ranked = Fuzzy.rank("clip", items) { rowText(kind: .text, text: $0) }
        XCTAssertEqual(ranked.map(\.item), ["xclipx", "c_l_i_p", "cxlxixp"])
    }
}
