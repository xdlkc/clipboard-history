import AppKit
import ApplicationServices
import ClipboardCore

/// 模拟 ⌘V 与辅助功能授权检测。
enum Keyboard {
    private static let vKeyCode: CGKeyCode = 9

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 向当前前台应用发送 ⌘V。需要辅助功能授权,否则事件会被系统丢弃。
    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
        Log.debug("posted ⌘V")
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(StatusMenu.accessibilitySettingsURL)
    }

    /// 未授权时的引导弹窗。
    static func promptForAccessibility() {
        let text = StatusMenu.accessibilityAlert
        let alert = NSAlert()
        alert.messageText = text.message
        alert.informativeText = text.informative
        text.buttons.forEach { alert.addButton(withTitle: $0) }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
}
