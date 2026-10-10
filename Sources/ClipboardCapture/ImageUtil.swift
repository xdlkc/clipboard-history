import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ImageUtil {
    public static let thumbnailMaxPixels = 64

    /// 读取磁盘图片并转为 PNG。
    /// 新 SDK 中 `NSBitmapImageRep(contentsOfFile:)` 不可用(坑 2),走 NSImage → TIFF → NSBitmapImageRep。
    public static func pngData(fromFile path: String) -> Data? {
        guard let tiff = NSImage(contentsOfFile: path)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// 任意图片数据(PNG/TIFF 等)转 PNG。
    public static func pngData(from data: Data) -> Data? {
        NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
    }

    /// 像素尺寸。
    public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let rep = NSBitmapImageRep(data: data), rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    /// 长边不超过 64px 的 PNG 缩略图(小图不放大)。
    public static func thumbnail(from data: Data, maxPixels: Int = thumbnailMaxPixels) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    /// 按扩展名判断是否图片文件。
    public static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension
        guard !ext.isEmpty else { return false }
        return UTType(filenameExtension: ext)?.conforms(to: .image) ?? false
    }
}
