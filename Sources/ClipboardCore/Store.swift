import Foundation
import SQLite3

public struct StoreError: Error, CustomStringConvertible {
    public let description: String
}

/// SQLite 持久化。只在主线程使用。
public final class Store {
    /// 每次数据变更后在 `notificationCenter` 上广播,object 为 Store 本身。
    public static let didChangeNotification = Notification.Name("ClipboardHistory.StoreDidChange")

    public static let retentionDays = 90
    public static let maxUnpinnedItems = 1000

    /// `~/Library/Application Support/ClipboardHistory/history.db`
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipboardHistory", isDirectory: true)
            .appendingPathComponent("history.db")
    }

    /// 测试用:设置后数据库改用该路径,不碰真实历史。
    public static let databasePathEnvironmentKey = "CLIPBOARD_HISTORY_DB"

    /// 环境变量 `CLIPBOARD_HISTORY_DB` 非空时用它,否则用 `defaultURL`。
    public static func resolvedURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment[databasePathEnvironmentKey], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return defaultURL
    }

    /// 列表查询的列,只取 thumb,不取 image。
    static let listColumns = ["id", "kind", "text", "thumb", "app", "created_at", "pinned", "content_hash"]
    static let listOrder = "ORDER BY pinned DESC, created_at DESC, id DESC"

    public let url: URL
    private let now: () -> Date
    private let notificationCenter: NotificationCenter
    private var db: OpaquePointer?

    public init(url: URL = Store.defaultURL,
                now: @escaping () -> Date = Date.init,
                notificationCenter: NotificationCenter = .default) throws {
        self.url = url
        self.now = now
        self.notificationCenter = notificationCenter

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            sqlite3_close(handle)
            throw StoreError(description: "打开数据库失败 \(url.path): \(message)")
        }
        db = handle
        sqlite3_busy_timeout(handle, 2000)
        try exec("PRAGMA journal_mode=WAL")
        try exec("""
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind INTEGER NOT NULL,
                text TEXT NOT NULL,
                image BLOB,
                thumb BLOB,
                app TEXT,
                created_at REAL NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0,
                content_hash TEXT NOT NULL UNIQUE
            )
            """)
        try exec("CREATE INDEX IF NOT EXISTS items_order ON items(pinned DESC, created_at DESC)")
    }

    deinit {
        sqlite3_close_v2(db)
    }

    // MARK: - 写入

    /// 插入;同 content_hash 已存在时只刷新 created_at(去重并置顶)。返回条目 id。
    @discardableResult
    public func insert(_ content: ClipboardContent, app: String?) throws -> Int64 {
        let stmt = try prepare("""
            INSERT INTO items (kind, text, image, thumb, app, created_at, pinned, content_hash)
            VALUES (?, ?, ?, ?, ?, ?, 0, ?)
            ON CONFLICT(content_hash) DO UPDATE SET created_at=excluded.created_at
            RETURNING id
            """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(content.kind.rawValue))
        bind(stmt, 2, content.text)
        bind(stmt, 3, content.image)
        bind(stmt, 4, content.thumb)
        bind(stmt, 5, app)
        sqlite3_bind_double(stmt, 6, now().timeIntervalSince1970)
        bind(stmt, 7, content.contentHash)
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw lastError("插入") }
        let id = sqlite3_column_int64(stmt, 0)
        sqlite3_step(stmt)
        didChange()
        return id
    }

    public func delete(id: Int64) throws {
        try run("DELETE FROM items WHERE id = ?", id)
    }

    /// 切换固定状态,返回切换后的状态;条目不存在返回 nil。
    @discardableResult
    public func togglePin(id: Int64) throws -> Bool? {
        try run("UPDATE items SET pinned = 1 - pinned WHERE id = ?", id)
        let stmt = try prepare("SELECT pinned FROM items WHERE id = ?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int(stmt, 0) != 0 : nil
    }

    public func setPinned(id: Int64, _ pinned: Bool) throws {
        try run("UPDATE items SET pinned = ? WHERE id = ?", pinned ? 1 : 0, id)
    }

    /// 清空未固定历史,固定项保留。
    public func clearUnpinned() throws {
        try run("DELETE FROM items WHERE pinned = 0")
    }

    /// 保留策略(启动时调用):删除超过 90 天的未固定条目,未固定条目最多保留最新的 1000 条;固定项豁免。
    public func applyRetention() throws {
        let cutoff = now().addingTimeInterval(-Double(Store.retentionDays) * 86_400).timeIntervalSince1970
        let changedBefore = sqlite3_total_changes(db)
        try run("DELETE FROM items WHERE pinned = 0 AND created_at < ?", cutoff, notify: false)
        try run("""
            DELETE FROM items WHERE pinned = 0 AND id NOT IN (
                SELECT id FROM items WHERE pinned = 0 ORDER BY created_at DESC, id DESC LIMIT ?
            )
            """, Int64(Store.maxUnpinnedItems), notify: false)
        if sqlite3_total_changes(db) != changedBefore { didChange() }
    }

    // MARK: - 读取

    /// 全部条目,固定在前、新的在前。不含完整图片。
    public func items() throws -> [HistoryItem] {
        let stmt = try prepare("SELECT \(Store.listColumns.joined(separator: ", ")) FROM items \(Store.listOrder)")
        defer { sqlite3_finalize(stmt) }
        var result: [HistoryItem] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw lastError("查询") }
            result.append(HistoryItem(
                id: sqlite3_column_int64(stmt, 0),
                kind: ItemKind(rawValue: Int(sqlite3_column_int(stmt, 1))) ?? .text,
                text: columnText(stmt, 2) ?? "",
                thumb: columnData(stmt, 3),
                app: columnText(stmt, 4),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                pinned: sqlite3_column_int(stmt, 6) != 0,
                contentHash: columnText(stmt, 7) ?? ""
            ))
        }
        return result
    }

    /// 按 id 懒加载完整图片 PNG。
    public func image(id: Int64) throws -> Data? {
        let stmt = try prepare("SELECT image FROM items WHERE id = ?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        return sqlite3_step(stmt) == SQLITE_ROW ? columnData(stmt, 0) : nil
    }

    public func count() throws -> Int {
        let stmt = try prepare("SELECT COUNT(*) FROM items")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw lastError("计数") }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// 读取单个 PRAGMA 的值(测试用)。
    func pragma(_ name: String) throws -> String? {
        let stmt = try prepare("PRAGMA \(name)")
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? columnText(stmt, 0) : nil
    }

    // MARK: - SQLite 辅助

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func didChange() {
        notificationCenter.post(name: Store.didChangeNotification, object: self)
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError(sql) }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError(sql) }
        return stmt
    }

    /// 执行一条无结果的语句;有行变化时广播。
    private func run(_ sql: String, _ args: Any..., notify: Bool = true) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            let index = Int32(i + 1)
            switch arg {
            case let v as Int64: sqlite3_bind_int64(stmt, index, v)
            case let v as Int: sqlite3_bind_int64(stmt, index, Int64(v))
            case let v as Double: sqlite3_bind_double(stmt, index, v)
            case let v as String: bind(stmt, index, v)
            default: throw StoreError(description: "不支持的参数类型 \(type(of: arg))")
            }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError(sql) }
        if notify, sqlite3_changes(db) > 0 { didChange() }
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, Int32(value.utf8.count), Store.transient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: Data?) {
        guard let value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        if value.isEmpty {
            sqlite3_bind_zeroblob(stmt, index, 0)
            return
        }
        value.withUnsafeBytes { buf in
            _ = sqlite3_bind_blob(stmt, index, buf.baseAddress, Int32(buf.count), Store.transient)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let p = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: p, count: count), as: UTF8.self)
    }

    private func columnData(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard let p = sqlite3_column_blob(stmt, index) else { return Data() }
        return Data(bytes: p, count: count)
    }

    private func lastError(_ context: String) -> StoreError {
        StoreError(description: "\(context): \(String(cString: sqlite3_errmsg(db)))")
    }
}
