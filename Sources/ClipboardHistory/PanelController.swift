import AppKit
import ClipboardCore

/// 无边框、不激活应用但可成为 key 的浮动面板。⌘ 组合键交给控制器处理。
final class KeyPanel: NSPanel {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Alfred 式主面板:搜索框 + 列表 + 右侧预览 + 底部状态栏。
final class PanelController: NSObject {
    typealias ChooseMode = PasteCoordinator.Mode

    /// 用户选定条目(面板已先隐藏)。写剪贴板与模拟粘贴由调用方负责。
    var onChoose: ((HistoryItem, ChooseMode) -> Void)?
    var isAccessibilityTrusted: () -> Bool = Keyboard.isAccessibilityTrusted

    private let store: Store
    private var model = PanelModel()
    private let panel: KeyPanel
    private let searchField = NSTextField()
    private let countField = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let preview = PreviewView()
    private let counterField = NSTextField(labelWithString: "")
    private var mouseMonitor: Any?
    private var renderNow = Date()
    /// 输入防抖:最后一次输入 50ms 后才过滤;方向键 / 回车 / ESC 等操作前会立即执行待处理的过滤。
    private static let searchDebounce: TimeInterval = 0.05
    private var pendingQuery: DispatchWorkItem?
    /// hide() 调用后到下次 show() 之前为 true;orderOut 引发的 windowDidResignKey 不再重复隐藏。
    private var isHiding = false

    var isVisible: Bool { panel.isVisible }

    init(store: Store) {
        self.store = store
        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: PanelGeometry.size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        configurePanel()
        buildContent()
        preview.loadImage = { [weak store] id in (try? store?.image(id: id)) ?? nil }
        panel.keyEquivalentHandler = { [weak self] event in self?.handleKeyEquivalent(event) ?? false }
        panel.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange),
                                               name: Store.didChangeNotification, object: store)
    }

    // MARK: - 显示 / 隐藏

    func show() {
        guard !panel.isVisible else { return }
        isHiding = false
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen {
            panel.setFrame(PanelGeometry.frame(onScreen: screen.frame), display: false)
        }
        model.reset()
        searchField.stringValue = ""
        reload()

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        (panel.fieldEditor(false, for: searchField) as? NSTextView)?.insertionPointColor = Theme.caret
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                DispatchQueue.main.async { self?.hide() }
            }
        }
        Log.debug("panel show frame=\(NSStringFromRect(panel.frame)) rows=\(model.rows.count)")
    }

    /// 立即隐藏(不做淡出):选定条目后 120ms 就要模拟 ⌘V,面板必须先交出 key 窗口。
    func hide() {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        pendingQuery?.cancel()
        pendingQuery = nil
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        panel.orderOut(nil)
        releaseContent()
        Log.debug("panel hide")
    }

    /// 隐藏后释放条目、rowText 缓存与预览内容,下次唤出时重新加载。
    private func releaseContent() {
        model = PanelModel()
        tableView.reloadData()
        preview.clear()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: - 数据

    @objc private func storeDidChange() {
        guard panel.isVisible else { return }
        reload()
    }

    private func reload() {
        do {
            model.setItems(try store.items())
        } catch {
            Log.debug("load items failed: \(error)")
        }
        renderNow = Date()
        tableView.reloadData()
        syncSelection()
    }

    private func syncSelection() {
        if let index = model.selectedIndex {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else {
            tableView.deselectAll(nil)
        }
        countField.stringValue = PanelFormat.searchCount(query: model.query, results: model.rows.count)
        counterField.stringValue = PanelFormat.statusCounter(selectedIndex: model.selectedIndex, total: model.rows.count,
                                                            accessibilityTrusted: isAccessibilityTrusted())
        let item = model.selectedRow?.item
        preview.show(item, appName: AppInfo.lookup(item?.app)?.name, now: renderNow)
    }

    // MARK: - 操作

    private func moveSelection(by delta: Int) {
        model.moveSelection(by: delta)
        syncSelection()
        Log.debug("panel selected=\(model.selectedIndex.map { $0 + 1 } ?? 0)/\(model.rows.count)")
    }

    private func choose(_ mode: ChooseMode) {
        guard let item = model.selectedRow?.item else { return }
        Log.debug("panel choose id=\(item.id) mode=\(mode)")
        hide()
        onChoose?(item, mode)
    }

    private func escape() {
        switch model.escape() {
        case .clearedQuery:
            searchField.stringValue = ""
            reload()
            Log.debug("panel query cleared rows=\(model.rows.count)")
        case .hide:
            hide()
        }
    }

    private func deleteSelected() {
        guard let item = model.selectedRow?.item else { return }
        do { try store.delete(id: item.id) } catch { Log.debug("delete failed: \(error)") }
    }

    private func togglePinSelected() {
        guard let item = model.selectedRow?.item else { return }
        do { try store.togglePin(id: item.id) } catch { Log.debug("pin failed: \(error)") }
    }

    @objc private func rowClicked() {
        flushPendingQuery()
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        model.select(row)
        syncSelection()
        choose(.paste)
    }

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        flushPendingQuery()
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (flags, event.keyCode) {
        case ([.command], 36), ([.command], 76):
            choose(.copyOnly)
            return true
        case ([.command], 51):
            deleteSelected()
            return true
        case ([.command, .shift], _) where key == "p":
            togglePinSelected()
            return true
        default:
            break
        }
        // 无主菜单的菜单栏应用里,搜索框的编辑快捷键需自行转发
        guard flags == [.command] else { return false }
        let action: Selector?
        switch key {
        case "a": action = #selector(NSText.selectAll(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "v": action = #selector(NSText.paste(_:))
        case "x": action = #selector(NSText.cut(_:))
        case "z": action = Selector(("undo:"))
        default: action = nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }

    // MARK: - 构建界面

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .vibrantDark)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
    }

    private func buildContent() {
        let size = PanelGeometry.size
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(size: size, radius: Theme.cornerRadius)
        panel.contentView = effect

        let root = PanelBackgroundView(frame: effect.bounds)
        effect.addSubview(root)

        let searchBox = NSView(frame: NSRect(x: 12, y: 12, width: size.width - 24, height: 52))
        searchBox.wantsLayer = true
        searchBox.layer?.backgroundColor = Theme.searchBackground.cgColor
        searchBox.layer?.cornerRadius = 10
        root.addSubview(searchBox)

        let magnifier = NSImageView(frame: NSRect(x: 16, y: 15, width: 22, height: 22))
        magnifier.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "搜索")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        magnifier.contentTintColor = Theme.textSecondary
        searchBox.addSubview(magnifier)

        countField.font = .systemFont(ofSize: 12)
        countField.textColor = Theme.textCount
        countField.alignment = .right
        countField.frame = NSRect(x: searchBox.frame.width - 16 - 140, y: 17, width: 140, height: 16)
        searchBox.addSubview(countField)

        searchField.frame = NSRect(x: 50, y: 10, width: countField.frame.minX - 12 - 50, height: 32)
        searchField.font = Theme.searchFont
        searchField.textColor = Theme.textPrimary
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.usesSingleLineMode = true
        searchField.lineBreakMode = .byClipping
        searchField.cell?.isScrollable = true
        searchField.placeholderAttributedString = NSAttributedString(string: "搜索剪贴板历史", attributes: [
            .font: Theme.searchFont, .foregroundColor: Theme.textCount,
        ])
        searchField.delegate = self
        searchBox.addSubview(searchField)

        let listScroll = NSScrollView(frame: NSRect(x: 12, y: 72, width: PanelGeometry.listWidth, height: 342))
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.scrollerStyle = .overlay
        listScroll.borderType = .noBorder
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = PanelGeometry.listWidth
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = PanelGeometry.rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.refusesFirstResponder = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        listScroll.documentView = tableView
        root.addSubview(listScroll)

        let divider = NSView(frame: NSRect(x: 472, y: 72, width: 1, height: 342))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.divider.cgColor
        root.addSubview(divider)

        preview.frame = NSRect(x: 476, y: 72, width: size.width - 476 - 12, height: 342)
        root.addSubview(preview)

        root.addSubview(buildStatusBar(width: size.width, y: size.height - 32))
    }

    private func buildStatusBar(width: CGFloat, y: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: y, width: width, height: 32))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.statusBackground.cgColor
        let border = NSView(frame: NSRect(x: 0, y: 31, width: width, height: 1))
        border.wantsLayer = true
        border.layer?.backgroundColor = Theme.statusBorder.cgColor
        border.autoresizingMask = [.width, .minYMargin]
        bar.addSubview(border)

        counterField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        counterField.textColor = Theme.textEmphasis
        var views: [NSView] = [counterField]
        for hint in PanelFormat.keyHints {
            let cap = KeyCapLabel(labelWithString: hint.key)
            let label = Self.statusLabel(hint.label)
            let pair = NSStackView(views: [cap, label])
            pair.spacing = 5
            views.append(pair)
        }
        let hotkey = Self.statusLabel(PanelFormat.hotkeyHint)
        hotkey.sizeToFit()
        hotkey.frame.origin = NSPoint(x: width - 18 - hotkey.frame.width, y: ((31 - hotkey.frame.height) / 2).rounded())
        bar.addSubview(hotkey)

        // 计数文字会变长,左侧一组占满热键提示之前的全部宽度,内容靠左排列
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 16
        stack.alignment = .centerY
        stack.frame = NSRect(x: 18, y: 0, width: hotkey.frame.minX - 16 - 18, height: 31)
        bar.addSubview(stack)
        return bar
    }

    private static func statusLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = Theme.textTertiary
        return label
    }

    private static func roundedMask(size: NSSize, radius: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - 搜索框

extension PanelController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        pendingQuery?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyQuery() }
        pendingQuery = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.searchDebounce, execute: work)
    }

    private func flushPendingQuery() {
        guard let work = pendingQuery else { return }
        work.cancel()
        applyQuery()
    }

    private func applyQuery() {
        pendingQuery = nil
        model.setQuery(searchField.stringValue)
        renderNow = Date()
        tableView.reloadData()
        syncSelection()
        Log.debug("panel query=\(model.query) rows=\(model.rows.count) selected=\(model.selectedIndex.map { $0 + 1 } ?? 0)")
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        flushPendingQuery()
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
        case #selector(NSResponder.insertNewline(_:)):
            choose(.paste)
        case #selector(NSResponder.cancelOperation(_:)):
            escape()
        default:
            return false
        }
        return true
    }
}

// MARK: - 窗口

extension PanelController: NSWindowDelegate {
    /// ⌘Tab 切换应用、切换桌面等让面板失去 key 时隐藏。
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

// MARK: - 列表

extension PanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        model.rows.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SelectionRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard model.rows.indices.contains(row) else { return nil }
        let view = tableView.makeView(withIdentifier: RowView.identifier, owner: nil) as? RowView ?? RowView()
        view.configure(model.rows[row], now: renderNow, selected: tableView.isRowSelected(row))
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row != model.selectedIndex else { return }
        model.select(row)
        syncSelection()
    }
}

/// 面板背景:设计稿的深色渐变 + 1px 内描边,子视图使用左上原点坐标。
private final class PanelBackgroundView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: Theme.cornerRadius, yRadius: Theme.cornerRadius)
        NSGradient(starting: Theme.panelTop, ending: Theme.panelBottom)?.draw(in: path, angle: 90)
        Theme.panelBorder.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                  xRadius: Theme.cornerRadius - 0.5, yRadius: Theme.cornerRadius - 0.5)
        border.lineWidth = 1
        border.stroke()
    }
}

/// 状态栏键帽:圆角浅色底的小号文字。
private final class KeyCapLabel: NSTextField {
    convenience init(labelWithString string: String) {
        self.init(frame: .zero)
        stringValue = string
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        font = .systemFont(ofSize: 10.5)
        textColor = Theme.textEmphasis
        wantsLayer = true
        layer?.backgroundColor = Theme.keyCapBackground.cgColor
        layer?.cornerRadius = 4
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 10, height: size.height + 2)
    }
}
