import CoreGraphics
import Foundation

/// 主面板的状态:历史条目、查询、过滤结果与选中项。与 UI 无关,可单元测试。
public struct PanelModel {
    public struct Row {
        public let item: HistoryItem
        /// 在 `item.rowText` 上的匹配结果;空查询时分数为 0、无区间。
        public let match: FuzzyMatch
    }

    public enum EscapeResult: Equatable {
        case clearedQuery
        case hide
    }

    public private(set) var items: [HistoryItem] = []
    public private(set) var query = ""
    public private(set) var rows: [Row] = []
    public private(set) var selectedIndex: Int?

    private var rowTextCache: [Int64: RowText] = [:]

    public init() {}

    public var selectedRow: Row? { selectedIndex.map { rows[$0] } }

    /// 替换全部条目(热刷新)。尽量保持选中同一条目,否则保持原位置。
    public mutating func setItems(_ newItems: [HistoryItem]) {
        let previousId = selectedRow?.item.id
        let previousIndex = selectedIndex
        var cache: [Int64: RowText] = [:]
        cache.reserveCapacity(newItems.count)
        for item in newItems {
            cache[item.id] = rowTextCache[item.id] ?? item.rowText
        }
        rowTextCache = cache
        items = newItems
        refilter()
        if let previousId, let index = rows.firstIndex(where: { $0.item.id == previousId }) {
            selectedIndex = index
        } else {
            selectedIndex = clamp(previousIndex ?? 0)
        }
    }

    /// 修改查询:重新过滤,选中第一项。
    public mutating func setQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        refilter()
        selectedIndex = clamp(0)
    }

    /// 上下移动选中项,到两端停住。
    public mutating func moveSelection(by delta: Int) {
        guard !rows.isEmpty else {
            selectedIndex = nil
            return
        }
        selectedIndex = clamp((selectedIndex ?? 0) + delta)
    }

    public mutating func select(_ index: Int) {
        selectedIndex = rows.indices.contains(index) ? index : selectedIndex
    }

    /// ESC:有查询词时先清空,再按才关闭面板。
    public mutating func escape() -> EscapeResult {
        guard !query.isEmpty else { return .hide }
        setQuery("")
        return .clearedQuery
    }

    /// 面板重新唤出时调用:清空查询并选中第一项。
    public mutating func reset() {
        query = ""
        refilter()
        selectedIndex = clamp(0)
    }

    private mutating func refilter() {
        let cache = rowTextCache
        rows = Fuzzy.rank(query, items) { cache[$0.id] ?? $0.rowText }.map { Row(item: $0.item, match: $0.match) }
    }

    private func clamp(_ index: Int) -> Int? {
        rows.isEmpty ? nil : min(max(index, 0), rows.count - 1)
    }
}

/// 列表行标题:显示 rowText 的前若干字符,高亮区间由 `Highlight` 裁剪到同一显示串上(坑 1)。
public enum RowTitle {
    /// 单行标题最多显示的字符数,其余反正会被截断。
    public static let maxCharacters = 400

    public static func display(_ match: FuzzyMatch, maxCharacters: Int = maxCharacters) -> (string: String, highlights: [NSRange]) {
        let full = match.target.string
        let string = full.count > maxCharacters ? String(full.prefix(maxCharacters)) : full
        return (string, match.nsRanges(clampedTo: (string as NSString).length))
    }
}

/// 面板几何:1064×454,水平居中,距屏幕顶部 80pt;左侧列表 452、右侧预览 588。
public enum PanelGeometry {
    public static let size = CGSize(width: 1064, height: 454)
    public static let topInset: CGFloat = 80
    public static let listWidth: CGFloat = 452
    public static let previewWidth: CGFloat = 588
    public static let rowHeight: CGFloat = 46

    /// `screenFrame` 为屏幕在 AppKit 坐标系(左下为原点)中的 frame。
    public static func frame(onScreen screenFrame: CGRect) -> CGRect {
        let x = (screenFrame.midX - size.width / 2).rounded()
        let y = screenFrame.maxY - topInset - size.height
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
