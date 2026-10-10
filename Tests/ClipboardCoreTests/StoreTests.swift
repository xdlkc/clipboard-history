import XCTest
@testable import ClipboardCore

final class StoreTests: XCTestCase {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private var dir: URL!
    private var clock: Clock!
    private var center: NotificationCenter!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("StoreTests-\(UUID().uuidString)")
        clock = Clock()
        center = NotificationCenter()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore() throws -> Store {
        let clock = self.clock!
        return try Store(url: dir.appendingPathComponent("nested/history.db"), now: { clock.now }, notificationCenter: center)
    }

    @discardableResult
    private func insertText(_ store: Store, _ text: String, advance: TimeInterval = 1) throws -> Int64 {
        clock.advance(advance)
        return try store.insert(.text(text), app: "com.example.app")
    }

    private func image(_ seed: UInt8, size: Int = 4096) -> ClipboardContent {
        .image(png: Data(repeating: seed, count: size), width: 10, height: 20, thumb: Data([seed, 1, 2]))
    }

    func testDefaultURLIsInApplicationSupport() {
        XCTAssertTrue(Store.defaultURL.path.hasSuffix("Library/Application Support/ClipboardHistory/history.db"),
                      Store.defaultURL.path)
    }

    func testResolvedURLUsesEnvironmentOverride() {
        XCTAssertEqual(Store.resolvedURL(environment: [:]), Store.defaultURL)
        XCTAssertEqual(Store.resolvedURL(environment: ["CLIPBOARD_HISTORY_DB": ""]), Store.defaultURL)
        XCTAssertEqual(Store.resolvedURL(environment: ["CLIPBOARD_HISTORY_DB": "/tmp/x/h.db"]).path, "/tmp/x/h.db")
    }

    func testCreatesDirectoryAndUsesWALAndBusyTimeout() throws {
        let store = try makeStore()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
        XCTAssertEqual(try store.pragma("journal_mode"), "wal")
        XCTAssertEqual(try store.pragma("busy_timeout"), "2000")
    }

    func testInsertAndListFields() throws {
        let store = try makeStore()
        let id = try insertText(store, "hello")
        let items = try store.items()
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.text, "hello")
        XCTAssertEqual(item.app, "com.example.app")
        XCTAssertEqual(item.createdAt, clock.now)
        XCTAssertFalse(item.pinned)
        XCTAssertEqual(item.contentHash, ClipboardContent.text("hello").contentHash)
        XCTAssertNil(item.thumb)
    }

    func testTextWithEmbeddedNulAndUnicodeRoundTrips() throws {
        let store = try makeStore()
        let text = "a\u{0}b\n中文😀\r\n\t"
        try insertText(store, text)
        XCTAssertEqual(try store.items().first?.text, text)
    }

    func testUpsertDedupMovesItemToTopAndKeepsId() throws {
        let store = try makeStore()
        let first = try insertText(store, "first")
        try insertText(store, "second")
        try insertText(store, "third")
        XCTAssertEqual(try store.items().map(\.text), ["third", "second", "first"])

        let again = try insertText(store, "first")
        XCTAssertEqual(again, first)
        XCTAssertEqual(try store.count(), 3)
        let items = try store.items()
        XCTAssertEqual(items.map(\.text), ["first", "third", "second"])
        XCTAssertEqual(items.first?.createdAt, clock.now)
    }

    func testOrderingPinnedFirstThenNewest() throws {
        let store = try makeStore()
        let a = try insertText(store, "a")
        try insertText(store, "b")
        let c = try insertText(store, "c")
        try insertText(store, "d")
        XCTAssertEqual(try store.togglePin(id: a), true)
        try store.setPinned(id: c, true)
        XCTAssertEqual(try store.items().map(\.text), ["c", "a", "d", "b"])
        XCTAssertEqual(try store.items().map(\.pinned), [true, true, false, false])

        // 固定项再次复制:刷新时间,仍在固定区内置顶
        try insertText(store, "a")
        XCTAssertEqual(try store.items().map(\.text), ["a", "c", "d", "b"])

        XCTAssertEqual(try store.togglePin(id: a), false)
        XCTAssertEqual(try store.items().map(\.text), ["c", "a", "d", "b"])
        XCTAssertNil(try store.togglePin(id: 9999))
    }

    func testListQueryExcludesImageBlob() throws {
        XCTAssertTrue(Store.listColumns.contains("thumb"))
        XCTAssertFalse(Store.listColumns.contains("image"))

        let store = try makeStore()
        clock.advance(1)
        try store.insert(image(7), app: nil)
        let item = try XCTUnwrap(store.items().first)
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.text, "10×20")
        XCTAssertEqual(item.thumb, Data([7, 1, 2]))
    }

    func testLazyImageLoadById() throws {
        let store = try makeStore()
        clock.advance(1)
        let imageId = try store.insert(image(9, size: 100_000), app: nil)
        let textId = try insertText(store, "text")
        XCTAssertEqual(try store.image(id: imageId), Data(repeating: 9, count: 100_000))
        XCTAssertNil(try store.image(id: textId))
        XCTAssertNil(try store.image(id: 424242))
    }

    func testFileItemRoundTrip() throws {
        let store = try makeStore()
        clock.advance(1)
        try store.insert(.files(paths: ["/tmp/a.png", "/tmp/b c.txt"], thumb: Data([1])), app: "com.apple.finder")
        let item = try XCTUnwrap(store.items().first)
        XCTAssertEqual(item.kind, .file)
        XCTAssertEqual(item.text, "/tmp/a.png\n/tmp/b c.txt")
        XCTAssertEqual(item.rowText.string, "a.png, b c.txt")
        XCTAssertEqual(item.thumb, Data([1]))
    }

    func testDelete() throws {
        let store = try makeStore()
        let a = try insertText(store, "a")
        try insertText(store, "b")
        try store.delete(id: a)
        XCTAssertEqual(try store.items().map(\.text), ["b"])
    }

    func testClearUnpinnedKeepsPinned() throws {
        let store = try makeStore()
        let a = try insertText(store, "a")
        try insertText(store, "b")
        let c = try insertText(store, "c")
        try store.setPinned(id: a, true)
        try store.setPinned(id: c, true)
        try store.clearUnpinned()
        XCTAssertEqual(try store.items().map(\.text), ["c", "a"])
    }

    func testRetentionRemovesUnpinnedOlderThan90Days() throws {
        let store = try makeStore()
        let oldPinned = try insertText(store, "old pinned")
        try store.setPinned(id: oldPinned, true)
        try insertText(store, "old")
        try insertText(store, "boundary", advance: 1)
        clock.advance(90 * 86_400 - 1)
        try insertText(store, "recent", advance: 0)
        clock.advance(1)

        try store.applyRetention()
        XCTAssertEqual(try store.items().map(\.text), ["old pinned", "recent", "boundary"])

        clock.advance(1)
        try store.applyRetention()
        XCTAssertEqual(try store.items().map(\.text), ["old pinned", "recent"])
    }

    func testRetentionCapsUnpinnedAt1000AndExemptsPinned() throws {
        let store = try makeStore()
        var pinnedIds: [Int64] = []
        for i in 0..<3 {
            let id = try insertText(store, "pinned \(i)")
            try store.setPinned(id: id, true)
            pinnedIds.append(id)
        }
        for i in 0..<1005 {
            try insertText(store, "item \(i)")
        }
        XCTAssertEqual(try store.count(), 1008)

        try store.applyRetention()
        let items = try store.items()
        XCTAssertEqual(items.count, 1003)
        XCTAssertEqual(items.filter(\.pinned).count, 3)
        XCTAssertEqual(items.filter { !$0.pinned }.count, Store.maxUnpinnedItems)
        let texts = Set(items.map(\.text))
        for i in 0..<5 { XCTAssertFalse(texts.contains("item \(i)"), "最旧的 item \(i) 应被清理") }
        XCTAssertTrue(texts.contains("item 5"))
        XCTAssertTrue(texts.contains("item 1004"))
        XCTAssertEqual(items.first?.text, "pinned 2")
    }

    func testChangeNotificationsArePosted() throws {
        let store = try makeStore()
        var count = 0
        let token = center.addObserver(forName: Store.didChangeNotification, object: store, queue: nil) { _ in count += 1 }
        defer { center.removeObserver(token) }

        let a = try insertText(store, "a")
        XCTAssertEqual(count, 1)
        try insertText(store, "a")
        XCTAssertEqual(count, 2)
        try store.togglePin(id: a)
        XCTAssertEqual(count, 3)
        let b = try insertText(store, "b")
        try store.delete(id: b)
        XCTAssertEqual(count, 5)
        try store.clearUnpinned()
        XCTAssertEqual(count, 5, "没有未固定项可删时不广播")
        try insertText(store, "c")
        clock.advance(91 * 86_400)
        try store.applyRetention()
        XCTAssertEqual(count, 7)
        try store.applyRetention()
        XCTAssertEqual(count, 7, "保留策略未删除任何条目时不广播")
    }

    func testPersistsAcrossReopen() throws {
        var store: Store? = try makeStore()
        let id = try insertText(store!, "persisted")
        try store!.setPinned(id: id, true)
        store = nil

        let reopened = try makeStore()
        let item = try XCTUnwrap(reopened.items().first)
        XCTAssertEqual(item.text, "persisted")
        XCTAssertTrue(item.pinned)
    }
}
