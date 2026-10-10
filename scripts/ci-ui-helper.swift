// CI 用的 UI 辅助工具(scripts/ci-panel-smoke.sh 调用)。
//   windows <pid>      列出该进程在屏幕上的窗口:"id x y w h"(CG 坐标,左上为原点)
//   screen             主显示器尺寸:"w h"
//   trusted            当前进程是否已获辅助功能授权
//   type <text>        以键盘事件输入文本
//   key <name> [n]     按键 n 次:down / up / esc / return
import AppKit
import ApplicationServices

let args = CommandLine.arguments.dropFirst()

func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
    usleep(60_000)
}

func press(_ keyCode: CGKeyCode) {
    let source = CGEventSource(stateID: .hidSystemState)
    post(CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true))
    post(CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false))
}

switch args.first {
case "windows":
    guard let pid = args.dropFirst().first.flatMap(Int32.init) else { exit(64) }
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for info in list where (info[kCGWindowOwnerPID as String] as? Int32) == pid {
        guard let id = info[kCGWindowNumber as String] as? Int,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
        print(id, Int(bounds.minX), Int(bounds.minY), Int(bounds.width), Int(bounds.height))
    }
case "screen":
    let bounds = CGDisplayBounds(CGMainDisplayID())
    print(Int(bounds.width), Int(bounds.height))
case "trusted":
    print(AXIsProcessTrusted())
case "type":
    let text = args.dropFirst().joined(separator: " ")
    let source = CGEventSource(stateID: .hidSystemState)
    for ch in text {
        let units = Array(String(ch).utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            post(event)
        }
    }
case "key":
    let codes: [String: CGKeyCode] = ["down": 125, "up": 126, "esc": 53, "return": 36]
    guard let name = args.dropFirst().first, let code = codes[name] else { exit(64) }
    let count = args.dropFirst(2).first.flatMap(Int.init) ?? 1
    for _ in 0..<count { press(code) }
default:
    FileHandle.standardError.write(Data("usage: ci-ui-helper windows|screen|trusted|type|key\n".utf8))
    exit(64)
}
