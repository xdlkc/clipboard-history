import AppKit
import ClipboardCapture
import ClipboardCore

/// 轮询 `NSPasteboard.changeCount` 捕获新内容并入库。
final class ClipboardMonitor {
    static let pollInterval: TimeInterval = 0.35

    private let store: Store
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?

    init(store: Store, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in self?.poll() }
        // 弹窗 runModal(modalPanel)和菜单展开(eventTracking)期间也要继续捕获
        for mode in [RunLoop.Mode.common, .modalPanel, .eventTracking] {
            RunLoop.main.add(timer, forMode: mode)
        }
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard let content = PasteboardReader.read(pasteboard) else { return }
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        do {
            let id = try store.insert(content, app: app)
            Log.debug("captured id=\(id) kind=\(content.kind.rawValue) app=\(app ?? "-")")
        } catch {
            Log.debug("insert failed: \(error)")
        }
    }

    /// 把条目写回剪贴板,并立即同步 changeCount,不把自己的写入再录一次。
    @discardableResult
    func write(_ item: HistoryItem) -> Bool {
        let image = item.kind == .image ? (try? store.image(id: item.id)) ?? nil : nil
        guard let changeCount = ClipboardWriter.write(kind: item.kind, text: item.text, image: image, to: pasteboard) else {
            return false
        }
        lastChangeCount = changeCount
        return true
    }
}
