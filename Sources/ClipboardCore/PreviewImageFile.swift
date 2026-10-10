import Foundation

/// 预览栏读取磁盘图片文件的规则:先取文件大小,超过 20MB(与捕获上限一致)或取不到大小就不读,
/// 退回显示缩略图 / 路径。
public enum PreviewImageFile {
    public static let maxBytes = 20 * 1024 * 1024

    /// 普通文件的字节数;不存在、不是普通文件或读不到时返回 nil。
    public static func fileSize(atPath path: String) -> Int? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else { return nil }
        return values.fileSize
    }

    public static func shouldLoad(fileSize: Int?, maxBytes: Int = maxBytes) -> Bool {
        guard let fileSize else { return false }
        return fileSize > 0 && fileSize <= maxBytes
    }

    /// 符合大小限制时读取文件内容,否则返回 nil 且不读文件。会访问磁盘,不要在主线程调用。
    public static func read(atPath path: String, maxBytes: Int = maxBytes) -> Data? {
        guard shouldLoad(fileSize: fileSize(atPath: path), maxBytes: maxBytes) else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
    }
}
