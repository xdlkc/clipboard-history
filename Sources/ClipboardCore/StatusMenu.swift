import Foundation

/// 菜单栏菜单的结构与文案。
public enum StatusMenu {
    public enum Item: Equatable, Sendable {
        case openPanel
        case launchAtLogin
        case accessibilitySettings
        case clearUnpinned
        case quit

        public var title: String {
            switch self {
            case .openPanel: return "打开面板"
            case .launchAtLogin: return "登录自启"
            case .accessibilitySettings: return "辅助功能设置"
            case .clearUnpinned: return "清空未固定历史…"
            case .quit: return "退出"
            }
        }
    }

    /// 菜单项顺序,nil 为分隔线。
    public static let layout: [Item?] = [.openPanel, nil, .launchAtLogin, .accessibilitySettings, nil, .clearUnpinned, nil, .quit]

    /// 系统设置 › 隐私与安全性 › 辅助功能
    public static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    // MARK: - 热键

    /// 「打开面板」菜单项标题:热键注册失败(被其他应用占用)时标出 ⚠️。
    public static func openPanelTitle(hotkey: HotkeyConfig, registered: Bool) -> String {
        registered ? Item.openPanel.title : "\(Item.openPanel.title)(⚠️ \(hotkey.displayString) 不可用)"
    }

    public static func hotkeyUnavailableAlert(_ hotkey: HotkeyConfig) -> AlertText {
        AlertText(message: "全局快捷键 \(hotkey.displayString) 不可用",
                  informative: "这个快捷键可能已被其他应用占用。请在占用它的应用里改掉该快捷键后重新打开 ClipboardHistory;在此之前可以从菜单栏图标「打开面板」。",
                  buttons: ["好"])
    }

    // MARK: - 登录自启

    /// 对应 `SMAppService.Status`。
    public enum LoginItemStatus: Sendable {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
    }

    public enum CheckState: Equatable, Sendable {
        case on, off, mixed
    }

    /// 已启用打勾;已注册但待用户在系统设置中批准显示为混合状态。
    public static func checkState(for status: LoginItemStatus) -> CheckState {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .mixed
        case .notRegistered, .notFound: return .off
        }
    }

    /// 点击菜单项时:已启用或待批准则注销,否则注册。
    public static func shouldRegister(currentStatus: LoginItemStatus) -> Bool {
        switch currentStatus {
        case .enabled, .requiresApproval: return false
        case .notRegistered, .notFound: return true
        }
    }

    public struct AlertText: Equatable, Sendable {
        public let message: String
        public let informative: String
        public let buttons: [String]
    }

    public static func loginItemFailedAlert(register: Bool, error: String) -> AlertText {
        AlertText(message: register ? "无法开启登录自启" : "无法关闭登录自启",
                  informative: "请先将 ClipboardHistory 安装到 /Applications(应用程序)文件夹,再从那里打开后重试。\n\n\(error)",
                  buttons: ["好"])
    }

    public static let clearUnpinnedAlert = AlertText(
        message: "清空未固定的历史?",
        informative: "固定的条目会保留,其余历史将被删除且无法恢复。",
        buttons: ["清空", "取消"])

    public static let accessibilityAlert = AlertText(
        message: "需要辅助功能权限才能自动粘贴",
        informative: "内容已复制到剪贴板,可以手动按 ⌘V 粘贴。\n在「系统设置 › 隐私与安全性 › 辅助功能」中允许 ClipboardHistory 后,按 ↩ 即可直接粘贴到当前应用。",
        buttons: ["打开系统设置", "稍后"])
}
