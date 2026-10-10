import XCTest
@testable import ClipboardCore

final class PanelFormatTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        now = date(2026, 10, 10, 17, 44)
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    private func item(_ kind: ItemKind, _ text: String, app: String? = nil, at createdAt: Date? = nil, pinned: Bool = false) -> HistoryItem {
        HistoryItem(id: 1, kind: kind, text: text, thumb: nil, app: app, createdAt: createdAt ?? now, pinned: pinned, contentHash: "h")
    }

    func testThousands() {
        XCTAssertEqual(PanelFormat.thousands(0), "0")
        XCTAssertEqual(PanelFormat.thousands(999), "999")
        XCTAssertEqual(PanelFormat.thousands(1284), "1,284")
        XCTAssertEqual(PanelFormat.thousands(100_000), "100,000")
        XCTAssertEqual(PanelFormat.thousands(1_234_567), "1,234,567")
        XCTAssertEqual(PanelFormat.thousands(-1234), "-1,234")
    }

    func testByteCount() {
        XCTAssertEqual(PanelFormat.byteCount(512), "512 B")
        XCTAssertEqual(PanelFormat.byteCount(245_400), "245 KB")
        XCTAssertEqual(PanelFormat.byteCount(1_260_000), "1.3 MB")
        XCTAssertEqual(PanelFormat.byteCount(20 * 1024 * 1024), "21.0 MB")
        XCTAssertEqual(PanelFormat.byteCount(3_000_000_000), "3.0 GB")
    }

    func testRelativeTime() {
        func rel(_ d: Date) -> String { PanelFormat.relativeTime(d, now: now, calendar: calendar) }
        XCTAssertEqual(rel(now), "刚刚")
        XCTAssertEqual(rel(now.addingTimeInterval(-59)), "刚刚")
        XCTAssertEqual(rel(now.addingTimeInterval(-120)), "2 分钟前")
        XCTAssertEqual(rel(now.addingTimeInterval(-38 * 60)), "38 分钟前")
        XCTAssertEqual(rel(now.addingTimeInterval(-3600)), "1 小时前")
        XCTAssertEqual(rel(date(2026, 10, 10, 0, 5)), "17 小时前")
        XCTAssertEqual(rel(date(2026, 10, 9, 23, 59)), "昨天")
        XCTAssertEqual(rel(date(2026, 10, 9, 0, 0)), "昨天")
        XCTAssertEqual(rel(date(2026, 10, 7, 20, 0)), "3 天前")
        XCTAssertEqual(rel(date(2026, 10, 4, 9, 0)), "6 天前")
        XCTAssertEqual(rel(date(2026, 10, 3, 9, 0)), "10月3日")
        XCTAssertEqual(rel(date(2025, 12, 31, 9, 0)), "2025年12月31日")
    }

    func testAbsoluteTime() {
        func abs(_ d: Date) -> String { PanelFormat.absoluteTime(d, now: now, calendar: calendar) }
        XCTAssertEqual(abs(date(2026, 10, 10, 17, 44)), "今天 17:44")
        XCTAssertEqual(abs(date(2026, 10, 9, 9, 5)), "昨天 09:05")
        XCTAssertEqual(abs(date(2026, 10, 3, 17, 44)), "10月3日 17:44")
        XCTAssertEqual(abs(date(2025, 1, 2, 3, 4)), "2025年1月2日 03:04")
    }

    func testDetail() {
        XCTAssertEqual(PanelFormat.detail(item(.text, String(repeating: "a", count: 1284))), "1,284 字符")
        XCTAssertEqual(PanelFormat.detail(item(.text, "中文😀\n")), "4 字符")
        XCTAssertEqual(PanelFormat.detail(item(.image, "10×20")), "图片")
        XCTAssertEqual(PanelFormat.detail(item(.file, "/a/build-status.png")), "1 张图片")
        XCTAssertEqual(PanelFormat.detail(item(.file, "/a/x.png\n/a/y.JPG")), "2 张图片")
        XCTAssertEqual(PanelFormat.detail(item(.file, "/p/Package.swift\n/p/build.sh\n/p/package.sh")), "3 个文件")
        XCTAssertEqual(PanelFormat.detail(item(.file, "/a/x.png\n/a/notes.txt")), "2 个文件")
    }

    func testPreviewHeaderText() {
        let header = PanelFormat.previewHeader(item(.text, String(repeating: "x", count: 1284), app: "com.apple.Terminal"),
                                               appName: "终端", now: now, calendar: calendar)
        XCTAssertEqual(header.title, "文本")
        XCTAssertEqual(header.parts, ["1,284 字符", "终端", "今天 17:44"])
        XCTAssertEqual(header.joined, "文本 · 1,284 字符 · 终端 · 今天 17:44")
    }

    func testPreviewHeaderImage() {
        let i = item(.image, "1024×768")
        XCTAssertEqual(PanelFormat.previewHeader(i, appName: nil, now: now, calendar: calendar, imageBytes: 245_400).parts,
                       ["1024×768 · 245 KB", "今天 17:44"])
        XCTAssertEqual(PanelFormat.previewHeader(i, appName: "预览", now: now, calendar: calendar).parts,
                       ["1024×768", "预览", "今天 17:44"])
    }

    func testPreviewHeaderFiles() {
        let images = item(.file, "/a/1.png\n/a/2.png\n/a/3.heic", at: date(2026, 10, 9, 8, 0))
        let header = PanelFormat.previewHeader(images, appName: "访达", now: now, calendar: calendar, firstImageSize: (800, 600))
        XCTAssertEqual(header.joined, "图片文件 · 3 张 · 800×600 · 访达 · 昨天 08:00")

        let files = item(.file, "/a/1.png\n/a/b.txt")
        XCTAssertEqual(PanelFormat.previewHeader(files, appName: "", now: now, calendar: calendar).joined, "文件 · 2 个 · 今天 17:44")
    }

    func testPreviewTextTruncatesOver100kCharacters() {
        let short = String(repeating: "a", count: 100_000)
        XCTAssertEqual(PanelFormat.previewText(short).truncated, false)
        XCTAssertEqual(PanelFormat.previewText(short).text, short)

        let long = String(repeating: "中", count: 100_001)
        let result = PanelFormat.previewText(long)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.text.hasPrefix(String(repeating: "中", count: 100_000) + "\n\n"))
        XCTAssertFalse(result.text.hasPrefix(String(repeating: "中", count: 100_001)))
        XCTAssertTrue(result.text.hasSuffix("仅显示前 100,000 字符(共 100,001 字符)"))

        let emoji = PanelFormat.previewText("👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦", limit: 2)
        XCTAssertTrue(emoji.text.hasPrefix("👨‍👩‍👧‍👦👨‍👩‍👧‍👦\n"), "按字符簇截断,不切开 emoji")
    }

    func testStatusCounter() {
        XCTAssertEqual(PanelFormat.statusCounter(selectedIndex: 0, total: 7, accessibilityTrusted: true), "1 / 7")
        XCTAssertEqual(PanelFormat.statusCounter(selectedIndex: 6, total: 7, accessibilityTrusted: true), "7 / 7")
        XCTAssertEqual(PanelFormat.statusCounter(selectedIndex: nil, total: 0, accessibilityTrusted: true), "0 / 0")
        XCTAssertEqual(PanelFormat.statusCounter(selectedIndex: 2, total: 1234, accessibilityTrusted: false), "⚠️ 3 / 1234")
    }

    func testSearchCountAndHints() {
        XCTAssertEqual(PanelFormat.searchCount(query: "build", results: 7), "7 条匹配")
        XCTAssertEqual(PanelFormat.searchCount(query: "", results: 1000), "共 1,000 条")
        XCTAssertEqual(PanelFormat.keyHints.map(\.key), ["↩", "⌘↩", "⌘⌫", "⇧⌘P", "esc"])
        XCTAssertEqual(PanelFormat.keyHints.map(\.label), ["粘贴", "仅复制", "删除", "固定", "清空 / 关闭"])
        XCTAssertEqual(PanelFormat.hotkeyHint, "⌘⌥C 唤出 / 隐藏")
    }
}
