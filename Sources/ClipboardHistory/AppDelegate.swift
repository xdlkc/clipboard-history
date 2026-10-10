import AppKit
import ClipboardCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// 全局热键,默认 ⌘⌥C(外接 Windows 键盘时 Windows 键即 ⌘)。
    private let hotkeyConfig = HotkeyConfig.default

    private var statusItem: NSStatusItem?
    private var loginItem: NSMenuItem?
    private var openPanelItem: NSMenuItem?
    /// 最近激活的其他应用;唤出面板时前台可能是本应用(如刚关掉弹窗),粘贴要回到它。
    private var frontmost = FrontmostTracker<NSRunningApplication>()
    private var store: Store?
    private var monitor: ClipboardMonitor?
    private var panel: PanelController?
    private var hotkeys: HotkeyCenter?
    private lazy var paste = PasteCoordinator(
        isTrusted: Keyboard.isAccessibilityTrusted,
        schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) },
        postPaste: Keyboard.postCommandV,
        promptForAccessibility: Keyboard.promptForAccessibility)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        startCapture()
        setupPanel()
        trackFrontmostApp()
        let hotkeys = HotkeyCenter { [weak self] in self?.panel?.toggle() }
        let registered = hotkeys.register(hotkeyConfig)
        self.hotkeys = hotkeys
        applyHotkeyState(registered: registered)
        Log.debug("accessibility trusted=\(Keyboard.isAccessibilityTrusted())")
        if CommandLine.arguments.contains("--show") {
            panel?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        hotkeys?.unregister()
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
            self?.choose(item, mode: mode)
        }
        self.panel = panel
    }

    private func trackFrontmostApp() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication {
            frontmost.didActivate(app, isSelf: app.processIdentifier == selfPID)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationDidActivate(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        frontmost.didActivate(app, isSelf: app.processIdentifier == ProcessInfo.processInfo.processIdentifier)
    }

    /// 热键被占用时:菜单项标出 ⚠️ 并去掉快捷键显示,启动时提示一次。
    private func applyHotkeyState(registered: Bool) {
        openPanelItem?.title = StatusMenu.openPanelTitle(hotkey: hotkeyConfig, registered: registered)
        guard !registered else { return }
        openPanelItem?.keyEquivalent = ""
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.runAlert(StatusMenu.hotkeyUnavailableAlert(self.hotkeyConfig))
        }
    }

    /// 面板已隐藏;写剪贴板,↩ / 点击时再把 ⌘V 送到原前台应用。
    private func choose(_ item: HistoryItem, mode: PasteCoordinator.Mode) {
        if mode == .paste, NSApp.isActive {
            frontmost.lastExternal?.activate(options: [])
        }
        let outcome = paste.choose(mode) { monitor?.write(item) == true }
        Log.debug("choose id=\(item.id) outcome=\(outcome)")
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "剪贴板历史")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        for entry in StatusMenu.layout {
            guard let entry else {
                menu.addItem(.separator())
                continue
            }
            let menuItem = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
            menuItem.target = self
            switch entry {
            case .openPanel:
                menuItem.action = #selector(openPanel)
                openPanelItem = menuItem
                menuItem.keyEquivalent = hotkeyConfig.key
                menuItem.keyEquivalentModifierMask = [.command, .option]
            case .launchAtLogin:
                menuItem.action = #selector(toggleLaunchAtLogin)
                loginItem = menuItem
            case .accessibilitySettings:
                menuItem.action = #selector(openAccessibilitySettings)
            case .clearUnpinned:
                menuItem.action = #selector(clearUnpinned)
            case .quit:
                menuItem.action = #selector(NSApplication.terminate(_:))
                menuItem.target = NSApp
                menuItem.keyEquivalent = "q"
            }
            menu.addItem(menuItem)
        }
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        switch StatusMenu.checkState(for: Self.loginItemStatus) {
        case .on: loginItem?.state = .on
        case .off: loginItem?.state = .off
        case .mixed: loginItem?.state = .mixed
        }
    }

    @objc private func openPanel() {
        panel?.show()
    }

    @objc private func openAccessibilitySettings() {
        Keyboard.openAccessibilitySettings()
    }

    private static var loginItemStatus: StatusMenu.LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        default: return .notRegistered
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let register = StatusMenu.shouldRegister(currentStatus: Self.loginItemStatus)
        do {
            if register {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.debug("launch at login register=\(register) status=\(Self.loginItemStatus)")
        } catch {
            Log.debug("launch at login failed: \(error)")
            runAlert(StatusMenu.loginItemFailedAlert(register: register, error: error.localizedDescription))
        }
    }

    @objc private func clearUnpinned() {
        guard runAlert(StatusMenu.clearUnpinnedAlert) == .alertFirstButtonReturn else { return }
        do {
            try store?.clearUnpinned()
            Log.debug("cleared unpinned items")
        } catch {
            Log.debug("clear failed: \(error)")
        }
    }

    @discardableResult
    private func runAlert(_ text: StatusMenu.AlertText) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = text.message
        alert.informativeText = text.informative
        text.buttons.forEach { alert.addButton(withTitle: $0) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
