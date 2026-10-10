import Foundation

/// 列表中的一条历史。不含完整图片,大图通过 `Store.image(id:)` 懒加载。
public struct HistoryItem: Equatable, Sendable {
    public let id: Int64
    public let kind: ItemKind
    public let text: String
    public let thumb: Data?
    /// 捕获时前台应用的 bundleIdentifier。
    public let app: String?
    public let createdAt: Date
    public let pinned: Bool
    public let contentHash: String

    public init(id: Int64, kind: ItemKind, text: String, thumb: Data?, app: String?,
                createdAt: Date, pinned: Bool, contentHash: String) {
        self.id = id
        self.kind = kind
        self.text = text
        self.thumb = thumb
        self.app = app
        self.createdAt = createdAt
        self.pinned = pinned
        self.contentHash = contentHash
    }

    public var rowText: RowText { ClipboardCore.rowText(kind: kind, text: text) }
}
