import Foundation

/// 面板内容分类。链接仍以文本存储,无需迁移已有历史。
public enum HistoryFilter: CaseIterable, Sendable {
    case all, text, link, image, file

    public var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .link: return "链接"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    public func includes(_ item: HistoryItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text && !Self.isLink(item.text)
        case .link: return item.kind == .text && Self.isLink(item.text)
        case .image: return item.kind == .image
        case .file: return item.kind == .file
        }
    }

    /// 去掉首尾空白后,必须是单个完整的 HTTP(S) URL。
    /// 含链接的段落、多个 URL、无协议域名和其他协议均属于普通文本。
    private static func isLink(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URLComponents(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }
}
