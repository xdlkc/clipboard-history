import AppKit
import ClipboardCore

/// 以显式键位选择避免录制时被当前全局热键截获。
enum HotkeyEditor {
    static func run(current: HotkeyConfig, save: (HotkeyConfig) throws -> Void) {
        let alert = NSAlert()
        alert.messageText = "设置全局快捷键"
        alert.informativeText = "选择修饰键和 A–Z / 0–9 键位（按 ANSI 物理键位）。保存后立即生效。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "恢复默认")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 90))
        let modifiers: [(String, HotkeyConfig.Modifiers)] = [
            ("⌘ Command", .command), ("⌥ Option", .option),
            ("⌃ Control", .control), ("⇧ Shift", .shift),
        ]
        var buttons: [NSButton] = []
        for (index, entry) in modifiers.enumerated() {
            let button = NSButton(checkboxWithTitle: entry.0, target: nil, action: nil)
            button.frame = NSRect(x: (index % 2) * 190, y: 60 - (index / 2) * 28, width: 180, height: 24)
            button.state = current.modifiers.contains(entry.1) ? .on : .off
            view.addSubview(button)
            buttons.append(button)
        }
        let keys = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26))
        keys.addItems(withTitles: HotkeyConfig.supportedKeys.map { $0.key.uppercased() })
        keys.selectItem(withTitle: current.key.uppercased())
        view.addSubview(keys)
        alert.accessoryView = view
        NSApp.activate(ignoringOtherApps: true)
        while true {
            let response = alert.runModal()
            let candidate: HotkeyConfig
            switch response {
            case .alertFirstButtonReturn:
                var flags: HotkeyConfig.Modifiers = []
                for (index, button) in buttons.enumerated() where button.state == .on {
                    flags.insert(modifiers[index].1)
                }
                let key = HotkeyConfig.supportedKeys[keys.indexOfSelectedItem]
                candidate = HotkeyConfig(keyCode: key.code, modifiers: flags, key: key.key)
            case .alertThirdButtonReturn:
                candidate = .default
            default:
                return
            }
            do {
                try save(candidate)
                return
            } catch {
                let failure = NSAlert()
                failure.messageText = "无法设置快捷键"
                failure.informativeText = error.localizedDescription
                failure.runModal()
            }
        }
    }
}

extension HotkeyConfig {
    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
    }
}
