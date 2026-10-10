import CryptoKit
import Foundation

/// 一次捕获到的剪贴板内容,尚未入库。
public struct ClipboardContent: Equatable, Sendable {
    public let kind: ItemKind
    /// 文本:原文;图片:"宽×高";文件:换行分隔的完整路径。
    public let text: String
    /// 完整 PNG,仅图片条目。
    public let image: Data?
    /// 64px 缩略图 PNG。
    public let thumb: Data?
    public let contentHash: String

    public static func text(_ text: String) -> ClipboardContent {
        ClipboardContent(kind: .text, text: text, image: nil, thumb: nil,
                         contentHash: ContentHash.sha256(kind: .text, Data(text.utf8)))
    }

    public static func image(png: Data, width: Int, height: Int, thumb: Data?) -> ClipboardContent {
        ClipboardContent(kind: .image, text: "\(width)×\(height)", image: png, thumb: thumb,
                         contentHash: ContentHash.sha256(kind: .image, png))
    }

    public static func files(paths: [String], thumb: Data?) -> ClipboardContent {
        let text = paths.joined(separator: "\n")
        return ClipboardContent(kind: .file, text: text, image: nil, thumb: thumb,
                                contentHash: ContentHash.sha256(kind: .file, Data(text.utf8)))
    }
}

public enum ContentHash {
    /// SHA256(1 字节 kind + 内容) 的小写十六进制。kind 参与计算,不同类型的相同字节不会互相去重。
    /// 文本按 UTF-8 计算;图片按 PNG 数据计算;文件按换行分隔的路径计算。
    public static func sha256(kind: ItemKind, _ payload: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data([UInt8(kind.rawValue)]))
        hasher.update(data: payload)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
