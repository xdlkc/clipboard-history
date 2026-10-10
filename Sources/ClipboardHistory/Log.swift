import Foundation

/// 调试日志直写 stderr(坑 9)。
enum Log {
    static func debug(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data("[ClipboardHistory] \(message())\n".utf8))
    }
}
