import AppKit
import ClipboardCore

/// 列表行背景:选中时画系统蓝 55% 的圆角矩形。
final class SelectionRowView: NSTableRowView {
    override var isSelected: Bool {
        didSet { (subviews.first as? RowView)?.isSelectedRow = isSelected }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        Theme.selection.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {}
}

/// 列表行内容(46pt):内容图标 / 标题(高亮)/ 副标题(来源应用 + 相对时间 + 明细)/ 固定标记。
final class RowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("RowView")

    private static let thumbCache = NSCache<NSNumber, NSImage>()

    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let appIconView = NSImageView()
    private let subtitleField = NSTextField(labelWithString: "")
    private let pinView = NSImageView()

    private var row: PanelModel.Row?
    private var now = Date()
    private var iconIsSymbol = false

    var isSelectedRow = false {
        didSet { if oldValue != isSelectedRow { applyColors() } }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 5
        iconView.layer?.masksToBounds = true

        for field in [titleField, subtitleField] {
            field.lineBreakMode = .byTruncatingTail
            field.usesSingleLineMode = true
            field.maximumNumberOfLines = 1
            field.cell?.truncatesLastVisibleLine = true
        }

        appIconView.imageScaling = .scaleProportionallyUpOrDown

        let pinConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        pinView.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "已固定")?.withSymbolConfiguration(pinConfig)
        pinView.contentTintColor = Theme.pin
        pinView.imageScaling = .scaleProportionallyDown

        [iconView, titleField, appIconView, subtitleField, pinView].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ row: PanelModel.Row, now: Date, selected: Bool) {
        self.row = row
        self.now = now
        isSelectedRow = selected
        configureIcon(row.item)
        let app = AppInfo.lookup(row.item.app)
        appIconView.image = app?.icon
        appIconView.isHidden = app?.icon == nil
        pinView.isHidden = !row.item.pinned
        applyColors()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        iconView.frame = NSRect(x: 10, y: 9, width: 28, height: 28)
        let textX: CGFloat = 48
        let rightInset: CGFloat = pinView.isHidden ? 10 : 10 + 14 + 10
        let textWidth = max(0, width - textX - rightInset)
        titleField.frame = NSRect(x: textX, y: 6, width: textWidth, height: 17)
        var subtitleX = textX
        if !appIconView.isHidden {
            appIconView.frame = NSRect(x: textX, y: 25.5, width: 14, height: 14)
            subtitleX += 14 + 5
        }
        subtitleField.frame = NSRect(x: subtitleX, y: 25, width: max(0, textX + textWidth - subtitleX), height: 15)
        pinView.frame = NSRect(x: width - 10 - 14, y: 15, width: 14, height: 16)
    }

    private func configureIcon(_ item: HistoryItem) {
        if let thumb = thumbnail(item) {
            iconView.image = thumb
            iconIsSymbol = false
            return
        }
        let symbol: String
        switch item.kind {
        case .text: symbol = "doc.text"
        case .file: symbol = "folder.fill"
        case .image: symbol = "photo"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        iconIsSymbol = true
    }

    private func thumbnail(_ item: HistoryItem) -> NSImage? {
        guard let data = item.thumb else { return nil }
        let key = NSNumber(value: item.id)
        if let cached = Self.thumbCache.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        Self.thumbCache.setObject(image, forKey: key)
        return image
    }

    private func applyColors() {
        guard let row else { return }
        if iconIsSymbol {
            iconView.contentTintColor = row.item.kind == .file ? Theme.folder : (isSelectedRow ? .white : Theme.iconTint)
        } else {
            iconView.contentTintColor = nil
        }
        titleField.attributedStringValue = Self.title(row)
        subtitleField.attributedStringValue = subtitle(row.item)
    }

    static func title(_ row: PanelModel.Row) -> NSAttributedString {
        let display = RowTitle.display(row.match)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let title = NSMutableAttributedString(string: display.string, attributes: [
            .font: Theme.titleFont, .foregroundColor: Theme.textPrimary, .paragraphStyle: paragraph,
        ])
        for range in display.highlights {
            title.addAttributes([
                .backgroundColor: Theme.highlightBackground,
                .foregroundColor: Theme.highlightText,
                .font: Theme.titleHighlightFont,
            ], range: range)
        }
        return title
    }

    private func subtitle(_ item: HistoryItem) -> NSAttributedString {
        let color = isSelectedRow ? Theme.textSecondarySelected : Theme.textSecondary
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let base: [NSAttributedString.Key: Any] = [.font: Theme.subtitleFont, .foregroundColor: color, .paragraphStyle: paragraph]
        let dot: [NSAttributedString.Key: Any] = [.font: Theme.subtitleFont, .foregroundColor: color.withAlphaComponent(color.alphaComponent * 0.6),
                                                  .paragraphStyle: paragraph]
        var parts: [String] = []
        if let app = AppInfo.lookup(item.app) { parts.append(app.name) }
        parts.append(PanelFormat.relativeTime(item.createdAt, now: now))
        parts.append(PanelFormat.detail(item))

        let result = NSMutableAttributedString()
        for (i, part) in parts.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: " · ", attributes: dot)) }
            result.append(NSAttributedString(string: part, attributes: base))
        }
        return result
    }
}
