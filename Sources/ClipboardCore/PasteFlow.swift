import Foundation

/// 全局热键配置。键码与修饰键取值同 Carbon(`kVK_ANSI_C` = 8,`cmdKey` = 0x100,`optionKey` = 0x800)。
public struct HotkeyConfig: Equatable, Sendable {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 0x0100)
        public static let shift = Modifiers(rawValue: 0x0200)
        public static let option = Modifiers(rawValue: 0x0800)
        public static let control = Modifiers(rawValue: 0x1000)
    }

    public let keyCode: UInt32
    public let modifiers: Modifiers
    /// 键帽上的字符(小写),用于菜单项的 keyEquivalent。
    public let key: String

    public init(keyCode: UInt32, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// ⌘⌥C
    public static let `default` = HotkeyConfig(keyCode: 8, modifiers: [.command, .option], key: "c")

    /// 按规格的写法输出,如 "⌘⌥C"。
    public var displayString: String {
        var s = ""
        if modifiers.contains(.command) { s += "⌘" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.shift) { s += "⇧" }
        return s + key.uppercased()
    }
}

/// 选定条目后的粘贴流程:先写剪贴板;↩ / 点击时若已授权辅助功能,120ms 后模拟 ⌘V;
/// 未授权时内容仍已复制,首次粘贴弹窗引导。
public final class PasteCoordinator {
    public enum Mode: Sendable {
        /// ↩ / 点击
        case paste
        /// ⌘↩
        case copyOnly
    }

    public enum Outcome: Equatable, Sendable {
        case writeFailed
        case copiedOnly
        case pasteScheduled
        /// 未授权,本次弹窗引导
        case promptedForAccessibility
        /// 未授权,之前已引导过,只复制
        case copiedWithoutPermission
    }

    public static let pasteDelay: TimeInterval = 0.12

    private let isTrusted: () -> Bool
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let postPaste: () -> Void
    private let promptForAccessibility: () -> Void
    public private(set) var hasPrompted = false

    public init(isTrusted: @escaping () -> Bool,
                schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
                postPaste: @escaping () -> Void,
                promptForAccessibility: @escaping () -> Void) {
        self.isTrusted = isTrusted
        self.schedule = schedule
        self.postPaste = postPaste
        self.promptForAccessibility = promptForAccessibility
    }

    /// - Parameter write: 写剪贴板,成功返回 true。总是最先调用。
    @discardableResult
    public func choose(_ mode: Mode, write: () -> Bool) -> Outcome {
        guard write() else { return .writeFailed }
        guard mode == .paste else { return .copiedOnly }
        if isTrusted() {
            schedule(Self.pasteDelay, postPaste)
            return .pasteScheduled
        }
        guard !hasPrompted else { return .copiedWithoutPermission }
        hasPrompted = true
        promptForAccessibility()
        return .promptedForAccessibility
    }
}
