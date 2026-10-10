import Foundation
import UniformTypeIdentifiers

/// 面板上显示的各种文案。
public enum PanelFormat {
    // MARK: - 数字与大小

    /// 千分位:1284 → "1,284"。
    public static func thousands(_ n: Int) -> String {
        let digits = String(n.magnitude)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }

    /// 文件大小(1000 进制,与访达一致):"512 B"、"245 KB"、"1.2 MB"。
    public static func byteCount(_ bytes: Int) -> String {
        let b = Double(bytes)
        switch bytes {
        case ..<1000: return "\(bytes) B"
        case ..<1_000_000: return "\(Int((b / 1000).rounded())) KB"
        case ..<1_000_000_000: return String(format: "%.1f MB", b / 1_000_000)
        default: return String(format: "%.1f GB", b / 1_000_000_000)
        }
    }

    // MARK: - 时间

    /// 列表副标题用的相对时间:刚刚 / N 分钟前 / N 小时前(当天)/ 昨天 / N 天前(7 天内)/ M月d日 / yyyy年M月d日。
    public static func relativeTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600)) 小时前" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "昨天" }
        if days < 7 { return "\(days) 天前" }
        return dayString(date, now: now, calendar: calendar)
    }

    /// 预览栏头部的绝对时间:今天 17:44 / 昨天 09:05 / 10月3日 17:44 / 2025年10月3日 17:44。
    public static func absoluteTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hm = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: now) { return "今天 \(hm)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(hm)"
        }
        return "\(dayString(date, now: now, calendar: calendar)) \(hm)"
    }

    private static func dayString(_ date: Date, now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let md = "\(c.month ?? 0)月\(c.day ?? 0)日"
        return c.year == calendar.component(.year, from: now) ? md : "\(c.year ?? 0)年\(md)"
    }

    // MARK: - 条目明细

    /// 换行分隔的路径列表。
    public static func paths(of item: HistoryItem) -> [String] {
        item.text.split(whereSeparator: { $0.isNewline }).map(String.init)
    }

    public static func isImagePath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return UTType(filenameExtension: ext)?.conforms(to: .image) ?? false
    }

    /// 文件条目是否全部为图片文件。
    public static func allImageFiles(_ item: HistoryItem) -> Bool {
        let paths = paths(of: item)
        return item.kind == .file && !paths.isEmpty && paths.allSatisfy(isImagePath)
    }

    /// 列表副标题的明细:N 字符 / 图片 / N 张图片 / N 个文件。
    public static func detail(_ item: HistoryItem) -> String {
        switch item.kind {
        case .text: return "\(thousands(item.text.count)) 字符"
        case .image: return "图片"
        case .file:
            let n = paths(of: item).count
            return allImageFiles(item) ? "\(n) 张图片" : "\(n) 个文件"
        }
    }

    // MARK: - 预览栏头部

    public struct PreviewHeader: Equatable {
        /// 加粗的类型标签,如 "文本"。
        public let title: String
        /// 其后以 "·" 分隔的各段。
        public let parts: [String]

        public var joined: String { ([title] + parts).joined(separator: " · ") }
    }

    /// 预览栏头部:文本 "N 字符" / 图片 "宽×高 + 文件大小" / "图片文件 · N 张 · 宽×高" / "文件 · N 个",再接来源应用与时间。
    /// - Parameters:
    ///   - imageBytes: 图片条目的 PNG 字节数(懒加载后才知道)。
    ///   - firstImageSize: 全为图片文件时第一张图的像素尺寸。
    public static func previewHeader(_ item: HistoryItem, appName: String?, now: Date, calendar: Calendar = .current,
                                     imageBytes: Int? = nil, firstImageSize: (width: Int, height: Int)? = nil) -> PreviewHeader {
        var title: String
        var parts: [String]
        switch item.kind {
        case .text:
            title = "文本"
            parts = ["\(thousands(item.text.count)) 字符"]
        case .image:
            title = "图片"
            parts = [item.text + (imageBytes.map { " · " + byteCount($0) } ?? "")]
        case .file:
            let n = paths(of: item).count
            if allImageFiles(item) {
                title = "图片文件"
                parts = ["\(n) 张"] + (firstImageSize.map { ["\($0.width)×\($0.height)"] } ?? [])
            } else {
                title = "文件"
                parts = ["\(n) 个"]
            }
        }
        if let appName, !appName.isEmpty { parts.append(appName) }
        parts.append(absoluteTime(item.createdAt, now: now, calendar: calendar))
        return PreviewHeader(title: title, parts: parts)
    }

    // MARK: - 预览正文

    public static let previewCharacterLimit = 100_000

    /// 预览栏正文。超过 10 万字符时截断并在末尾标注。
    public static func previewText(_ text: String, limit: Int = previewCharacterLimit) -> (text: String, truncated: Bool) {
        var index = text.startIndex
        guard text.formIndex(&index, offsetBy: limit, limitedBy: text.endIndex), index < text.endIndex else {
            return (text, false)
        }
        let note = "\n\n…… 内容过长,仅显示前 \(thousands(limit)) 字符(共 \(thousands(text.count)) 字符)"
        return (String(text[..<index]) + note, true)
    }

    // MARK: - 状态栏与搜索框

    /// 状态栏左侧:"1 / 7";没有结果时 "0 / 0";未授权辅助功能时前缀 "⚠️ "。
    public static func statusCounter(selectedIndex: Int?, total: Int, accessibilityTrusted: Bool) -> String {
        let position = total == 0 ? 0 : (selectedIndex.map { $0 + 1 } ?? 0)
        return (accessibilityTrusted ? "" : "⚠️ ") + "\(position) / \(total)"
    }

    /// 搜索框右侧的计数:有查询时 "7 条匹配",否则 "共 N 条"。
    public static func searchCount(query: String, results: Int) -> String {
        query.isEmpty ? "共 \(thousands(results)) 条" : "\(thousands(results)) 条匹配"
    }

    /// 状态栏键位提示(键帽, 说明)。
    public static let keyHints: [(key: String, label: String)] = [
        ("↩", "粘贴"), ("⌘↩", "仅复制"), ("⌘⌫", "删除"), ("⇧⌘P", "固定"), ("esc", "清空 / 关闭"),
    ]

    public static let hotkeyHint = "⌘⌥C 唤出 / 隐藏"
}
