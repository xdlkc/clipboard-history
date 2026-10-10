import XCTest
@testable import ClipboardCore

final class PanelModelTests: XCTestCase {
    private func item(_ id: Int64, _ text: String, kind: ItemKind = .text, pinned: Bool = false) -> HistoryItem {
        HistoryItem(id: id, kind: kind, text: text, thumb: nil, app: nil,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(id)), pinned: pinned, contentHash: "h\(id)")
    }

    private var terminalOutput: String {
        "$ swift build -c release --arch arm64\r\nBuilding for production...\r\n[1/9] Compiling ClipboardHistory Fuzzy.swift\r\n" +
        "\twarning: 'NSBitmapImageRep(contentsOfFile:)' is unavailable 🚨\r\nBuild complete! (14.82s)\r\n"
    }

    private func sample() -> [HistoryItem] {
        [
            item(1, "./build.sh && open build/ClipboardHistory.app", pinned: true),
            item(2, terminalOutput),
            item(3, "/tmp/build-status.png", kind: .file),
            item(4, "Build failed: NSRange out of bounds\nat RowView.swift:88"),
            item(5, "1024×768", kind: .image),
            item(6, "BUILD_NUMBER=42 SIGN=adhoc ./package.sh"),
            item(7, "unrelated 中文 text"),
        ]
    }

    func testEmptyQueryShowsAllInStoreOrderAndSelectsFirst() {
        var model = PanelModel()
        XCTAssertNil(model.selectedIndex)
        model.setItems(sample())
        XCTAssertEqual(model.rows.map(\.item.id), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertTrue(model.rows.allSatisfy { $0.match.ranges.isEmpty })
    }

    func testQueryFiltersOnRowTextAndRanksByScore() {
        var model = PanelModel()
        model.setItems(sample())
        model.setQuery("build")
        XCTAssertEqual(Set(model.rows.map(\.item.id)), [1, 2, 3, 4, 6])
        XCTAssertEqual(model.selectedIndex, 0)
        let scores = model.rows.map(\.match.score)
        XCTAssertEqual(scores, scores.sorted(by: >))
        for row in model.rows {
            XCTAssertEqual(row.match.target, row.item.rowText, "必须在 rowText 上匹配(坑 1)")
        }
        model.setQuery("zzz")
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.selectedIndex)
    }

    func testFilePathsAreNotSearchable() {
        var model = PanelModel()
        model.setItems([item(1, "/Users/lkc/secret-folder/a.txt", kind: .file)])
        model.setQuery("secret")
        XCTAssertTrue(model.rows.isEmpty)
        model.setQuery("a.txt")
        XCTAssertEqual(model.rows.count, 1)
    }

    func testMoveSelectionClampsAtEnds() {
        var model = PanelModel()
        model.setItems(sample())
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedIndex, 0)
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedIndex, 2)
        model.moveSelection(by: 100)
        XCTAssertEqual(model.selectedIndex, 6)
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedIndex, 6)
        model.select(3)
        XCTAssertEqual(model.selectedRow?.item.id, 4)
        model.select(99)
        XCTAssertEqual(model.selectedIndex, 3)

        var empty = PanelModel()
        empty.moveSelection(by: 1)
        XCTAssertNil(empty.selectedIndex)
    }

    func testEscapeClearsQueryFirstThenHides() {
        var model = PanelModel()
        model.setItems(sample())
        model.setQuery("build")
        model.moveSelection(by: 2)
        XCTAssertEqual(model.escape(), .clearedQuery)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.rows.count, 7)
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.escape(), .hide)
        XCTAssertEqual(model.escape(), .hide)
    }

    func testHotRefreshKeepsSelectedItem() {
        var model = PanelModel()
        model.setItems(sample())
        model.select(3)
        var updated = sample()
        updated.insert(item(8, "new copy"), at: 1)
        model.setItems(updated)
        XCTAssertEqual(model.selectedRow?.item.id, 4)
        XCTAssertEqual(model.selectedIndex, 4)
    }

    func testDeletingSelectedItemKeepsPosition() {
        var model = PanelModel()
        model.setItems(sample())
        model.select(3)
        model.setItems(sample().filter { $0.id != 4 })
        XCTAssertEqual(model.selectedIndex, 3)
        XCTAssertEqual(model.selectedRow?.item.id, 5)

        model.select(5)
        model.setItems(sample().filter { $0.id <= 3 })
        XCTAssertEqual(model.selectedIndex, 2)
        model.setItems([])
        XCTAssertNil(model.selectedIndex)
    }

    func testPinToggleRefreshFollowsItem() {
        var model = PanelModel()
        model.setItems(sample())
        model.select(4)
        var pinnedFirst = sample()
        let moved = pinnedFirst.remove(at: 4)
        pinnedFirst.insert(HistoryItem(id: moved.id, kind: moved.kind, text: moved.text, thumb: nil, app: nil,
                                       createdAt: moved.createdAt, pinned: true, contentHash: moved.contentHash), at: 0)
        model.setItems(pinnedFirst)
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.selectedRow?.item.pinned, true)
    }

    func testResetClearsQuery() {
        var model = PanelModel()
        model.setItems(sample())
        model.setQuery("build")
        model.moveSelection(by: 1)
        model.reset()
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.rows.count, 7)
        XCTAssertEqual(model.selectedIndex, 0)
    }

    /// 坑 1 回归:多行终端输出在面板管线中搜索 + 上下切换 + 标题高亮转换,全程不越界。
    func testMultilineSearchAndArrowStepsProduceSafeHighlights() throws {
        var model = PanelModel()
        model.setItems(sample())
        for query in ["build", "warning", "🚨", "unavailable", "complete!", "Fuzzy.swift", "中文"] {
            model.setQuery(query)
            XCTAssertFalse(model.rows.isEmpty, query)
            for _ in 0..<(model.rows.count + 2) {
                let row = try XCTUnwrap(model.selectedRow)
                let display = RowTitle.display(row.match)
                let attributed = NSMutableAttributedString(string: display.string)
                for range in display.highlights {
                    XCTAssertLessThanOrEqual(NSMaxRange(range), attributed.length)
                    attributed.addAttribute(NSAttributedString.Key("hl"), value: true, range: range)
                }
                model.moveSelection(by: 1)
            }
            for _ in 0..<(model.rows.count + 2) { model.moveSelection(by: -1) }
            XCTAssertEqual(model.selectedIndex, 0)
        }
        model.setQuery("warning")
        let display = RowTitle.display(try XCTUnwrap(model.selectedRow).match)
        XCTAssertFalse(display.string.contains("\n"))
        XCTAssertEqual(display.highlights.map { (display.string as NSString).substring(with: $0) }, ["warning"])
    }

    func testRowTitleTruncatesLongTextAndClampsHighlights() throws {
        let long = String(repeating: "x", count: 1000) + " needle"
        let match = try XCTUnwrap(Fuzzy.match("xneedle", in: rowText(kind: .text, text: long)))
        let display = RowTitle.display(match, maxCharacters: 10)
        XCTAssertEqual(display.string, String(repeating: "x", count: 10))
        XCTAssertTrue(display.highlights.allSatisfy { NSMaxRange($0) <= 10 })

        let emoji = try XCTUnwrap(Fuzzy.match("👨‍👩‍👧‍👦", in: rowText(kind: .text, text: "ab👨‍👩‍👧‍👦cd")))
        let cut = RowTitle.display(emoji, maxCharacters: 3)
        XCTAssertEqual(cut.string, "ab👨‍👩‍👧‍👦")
        XCTAssertEqual(cut.highlights.map { (cut.string as NSString).substring(with: $0) }, ["👨‍👩‍👧‍👦"])
    }

    func testPanelGeometryIsTopCentered() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let frame = PanelGeometry.frame(onScreen: screen)
        XCTAssertEqual(frame.size, CGSize(width: 1064, height: 454))
        XCTAssertEqual(frame.minX, 332)
        XCTAssertEqual(frame.maxY, 1117 - 80)
        XCTAssertEqual(PanelGeometry.listWidth + PanelGeometry.previewWidth + 24, 1064)
        XCTAssertEqual(PanelGeometry.rowHeight, 46)

        let secondary = CGRect(x: 1728, y: -200, width: 1920, height: 1080)
        let f2 = PanelGeometry.frame(onScreen: secondary)
        XCTAssertEqual(f2.midX, secondary.midX)
        XCTAssertEqual(f2.maxY, secondary.maxY - 80)
    }
}
