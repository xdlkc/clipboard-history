import AppKit

/// 来源应用的名称与图标,按 bundleIdentifier 经 `NSWorkspace.urlForApplication` 解析并静态缓存。
struct AppInfo {
    let name: String
    let icon: NSImage?

    private static var cache: [String: AppInfo] = [:]

    static func lookup(_ bundleID: String?) -> AppInfo? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = cache[bundleID] { return cached }
        let info: AppInfo
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            info = AppInfo(name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name, icon: NSWorkspace.shared.icon(forFile: url.path))
        } else {
            info = AppInfo(name: bundleID, icon: nil)
        }
        cache[bundleID] = info
        return info
    }
}
