import AppKit
import ClipboardCore

/// 从剪贴板读取一条可入库的内容。
public enum PasteboardReader {
    /// 密码管理器等标记的敏感 / 临时内容,一律跳过。
    public static let skippedTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]

    public static let maxImageBytes = 20 * 1024 * 1024

    /// 读取优先级:文件 URL → 纯文本 → RTF(转纯文本)→ PNG → TIFF(转 PNG)。
    /// 敏感 / 临时内容、空剪贴板、超过 `maxImageBytes` 的图片返回 nil。
    public static func read(_ pasteboard: NSPasteboard, maxImageBytes: Int = maxImageBytes) -> ClipboardContent? {
        let types = pasteboard.types ?? []
        if types.contains(where: skippedTypes.contains) { return nil }

        let fileURLs = self.fileURLs(in: pasteboard)
        if !fileURLs.isEmpty {
            return .files(paths: fileURLs.map(\.path), thumb: fileThumbnail(fileURLs, pasteboard: pasteboard))
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text)
        }

        if let rtf = pasteboard.data(forType: .rtf),
           let text = NSAttributedString(rtf: rtf, documentAttributes: nil)?.string, !text.isEmpty {
            return .text(text)
        }

        if let png = pasteboard.data(forType: .png) {
            return image(png: png, maxBytes: maxImageBytes)
        }

        if let tiff = pasteboard.data(forType: .tiff), let png = ImageUtil.pngData(from: tiff) {
            return image(png: png, maxBytes: maxImageBytes)
        }

        return nil
    }

    /// 剪贴板中的文件 URL。macOS 26 SDK 没有 `urlFileURLsOnly`(坑 4),读出后手动过滤。
    public static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        return urls.filter { $0.isFileURL }
    }

    private static func image(png: Data, maxBytes: Int) -> ClipboardContent? {
        guard png.count <= maxBytes, let size = ImageUtil.pixelSize(of: png) else { return nil }
        return .image(png: png, width: size.width, height: size.height, thumb: ImageUtil.thumbnail(from: png))
    }

    /// 文件中有图片时,从第一个图片文件生成缩略图:优先用剪贴板里的 PNG 数据,否则读磁盘。
    private static func fileThumbnail(_ urls: [URL], pasteboard: NSPasteboard) -> Data? {
        guard let first = urls.first(where: ImageUtil.isImageFile) else { return nil }
        if let png = pasteboard.data(forType: .png), let thumb = ImageUtil.thumbnail(from: png) {
            return thumb
        }
        guard let png = ImageUtil.pngData(fromFile: first.path) else { return nil }
        return ImageUtil.thumbnail(from: png)
    }
}
