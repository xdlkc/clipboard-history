import AppKit
import ClipboardCore

/// 把历史条目写回剪贴板。调用方需用返回的 changeCount 同步监视器,避免把自己的写入再录一次。
public enum ClipboardWriter {
    /// - Parameter image: 图片条目的完整 PNG(由 `Store.image(id:)` 懒加载)。
    /// - Returns: 写入后的 changeCount;没有可写内容时返回 nil。
    @discardableResult
    public static func write(kind: ItemKind, text: String, image: Data?, to pasteboard: NSPasteboard) -> Int? {
        switch kind {
        case .text:
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .image:
            guard let image else { return nil }
            pasteboard.clearContents()
            pasteboard.setData(image, forType: .png)
        case .file:
            let urls = fileURLs(fromPaths: text)
            guard !urls.isEmpty else { return nil }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
            if urls.count == 1, ImageUtil.isImageFile(urls[0]), let png = ImageUtil.pngData(fromFile: urls[0].path) {
                pasteboard.setData(png, forType: .png)
            }
        }
        return pasteboard.changeCount
    }

    private static func fileURLs(fromPaths text: String) -> [URL] {
        text.split(whereSeparator: { $0.isNewline }).map { URL(fileURLWithPath: String($0)) }
    }
}
