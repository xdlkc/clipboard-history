import Foundation

/// 条目类型,数值与数据库 `items.kind` 一致。
public enum ItemKind: Int, Sendable {
    case text = 0
    case image = 1
    case file = 2
}

/// 列表行显示的文本。模糊匹配与高亮都只接受这个类型,
/// 保证匹配目标与显示文本是同一个字符串(坑 1)。
/// 只能通过 `rowText(kind:text:)` 构造。
public struct RowText: Hashable, Sendable {
    public let string: String

    fileprivate init(_ string: String) {
        self.string = string
    }
}

/// 换行在列表行里显示为这个记号。
public let rowNewlineMarker = " ⏎ "

/// 文件条目各文件名之间的分隔符。
public let rowFileSeparator = ", "

/// 列表行文本的唯一来源。
/// - 文本/图片:任何换行(`\n`、`\r\n`、`\r`、U+2028 等)展平为 `" ⏎ "`,`\t` 展平为空格。
///   `\r\n` 是一个字符簇,只产生一个 `" ⏎ "`。
/// - 文件:`text` 为换行分隔的完整路径,行文本只取文件名并以 `", "` 连接;完整路径只在预览栏显示。
public func rowText(kind: ItemKind, text: String) -> RowText {
    switch kind {
    case .text, .image:
        return RowText(flatten(text))
    case .file:
        return RowText(fileNames(fromPaths: text).map(flatten).joined(separator: rowFileSeparator))
    }
}

/// 从换行分隔的路径列表中取出文件名(忽略空行,目录末尾的 `/` 会被去掉)。
public func fileNames(fromPaths text: String) -> [String] {
    text.split(whereSeparator: { $0.isNewline }).compactMap { line -> String? in
        var path = Substring(line)
        while path.count > 1, path.hasSuffix("/") { path = path.dropLast() }
        guard !path.isEmpty else { return nil }
        if path == "/" { return "/" }
        if let slash = path.lastIndex(of: "/") {
            let name = path[path.index(after: slash)...]
            return name.isEmpty ? nil : String(name)
        }
        return String(path)
    }
}

private func flatten(_ text: String) -> String {
    var out = ""
    out.reserveCapacity(text.utf8.count)
    for ch in text {
        if ch.isNewline {
            out += rowNewlineMarker
        } else if ch == "\t" {
            out.append(" ")
        } else {
            out.append(ch)
        }
    }
    return out
}
