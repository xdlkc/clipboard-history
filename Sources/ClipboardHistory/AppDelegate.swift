import AppKit
import ClipboardCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var store: Store?
    private var monitor: ClipboardMonitor?
    private var panel: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        startCapture()
        setupPanel()
        if CommandLine.arguments.contains("--show") {
            panel?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    private func startCapture() {
        do {
            let store = try Store(url: Store.resolvedURL())
            try store.applyRetention()
            let monitor = ClipboardMonitor(store: store)
            monitor.start()
            self.store = store
            self.monitor = monitor
            Log.debug("store=\(store.url.path) items=\((try? store.count()) ?? -1)")
        } catch {
            Log.debug("store unavailable: \(error)")
        }
    }

    private func setupPanel() {
        guard let store else { return }
        let panel = PanelController(store: store)
        panel.onChoose = { [weak self] item, mode in
            guard let self else { return }
            self.panel?.hide()
            guard self.monitor?.write(item) == true else { return }
            if mode == .paste {
                // TODO(PR #4): 120ms 后模拟 ⌘V(Keyboard.swift);未授权辅助功能时首次弹窗引导
                Log.debug("paste requested id=\(item.id) (simulated ⌘V arrives in PR #4)")
            }
        }
        self.panel = panel
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "剪贴板历史")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
