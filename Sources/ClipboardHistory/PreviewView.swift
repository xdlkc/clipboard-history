import AppKit
import ClipboardCore

/// 右侧预览栏:头部小字 + 正文(等宽纯文本,或可缩放的图片)。
final class PreviewView: NSView {
    private let headerField = NSTextField(labelWithString: "")
    private let body = NSView()
    private let textScroll = NSScrollView()
    private let textView = NSTextView()
    private let imageScroll = NSScrollView()
    private let imageView = NSImageView()

    /// 单项图片缓存:(key, 图片, PNG 字节数)。
    private var cachedImage: (key: String, image: NSImage, bytes: Int)?
    private var shownKey: String?

    /// 按 id 懒加载图片条目的完整 PNG。
    var loadImage: (Int64) -> Data? = { _ in nil }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        headerField.lineBreakMode = .byTruncatingTail
        addSubview(headerField)

        body.wantsLayer = true
        body.layer?.backgroundColor = Theme.previewBackground.cgColor
        body.layer?.cornerRadius = 8
        body.layer?.masksToBounds = true
        addSubview(body)

        setupTextView()
        setupImageView()
        body.addSubview(textScroll)
        body.addSubview(imageScroll)
        imageScroll.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        headerField.frame = NSRect(x: 6, y: 4, width: bounds.width - 12, height: 15)
        body.frame = NSRect(x: 0, y: 32, width: bounds.width, height: bounds.height - 32)
        textScroll.frame = body.bounds
        imageScroll.frame = body.bounds
        if imageView.image != nil, imageScroll.magnification == 1 {
            imageView.frame = NSRect(origin: .zero, size: imageScroll.contentSize)
        }
    }

    private func setupTextView() {
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = true
        textScroll.hasHorizontalScroller = true
        textScroll.autohidesScrollers = true
        textScroll.scrollerStyle = .overlay
        textScroll.borderType = .noBorder

        // 坑 5:关闭富文本、链接与数据检测
        textView.isRichText = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.importsGraphics = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.font = Theme.previewFont
        textView.textColor = Theme.previewText
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.selectedTextAttributes = [.backgroundColor: Theme.selection]

        // 不折行(与设计稿 white-space: pre 一致),可横向滚动
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textScroll.documentView = textView
    }

    private func setupImageView() {
        imageScroll.drawsBackground = false
        imageScroll.hasVerticalScroller = true
        imageScroll.hasHorizontalScroller = true
        imageScroll.autohidesScrollers = true
        imageScroll.scrollerStyle = .overlay
        imageScroll.allowsMagnification = true
        imageScroll.minMagnification = 0.1
        imageScroll.maxMagnification = 8
        imageScroll.contentView = CenteringClipView()
        imageScroll.contentView.drawsBackground = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageScroll.documentView = imageView
    }

    /// 显示条目;同一条目重复调用不重置滚动位置。
    func show(_ item: HistoryItem?, appName: String?, now: Date) {
        guard let item else {
            shownKey = nil
            headerField.attributedStringValue = NSAttributedString()
            showText("")
            return
        }
        let key = "\(item.id):\(item.contentHash)"
        let sameItem = key == shownKey
        shownKey = key

        switch item.kind {
        case .text:
            setHeader(PanelFormat.previewHeader(item, appName: appName, now: now))
            if !sameItem { showText(PanelFormat.previewText(item.text).text) }
        case .image:
            let loaded = image(key: "id:\(item.id)") { self.loadImage(item.id) }
            setHeader(PanelFormat.previewHeader(item, appName: appName, now: now, imageBytes: loaded?.bytes))
            if !sameItem {
                if let loaded { showImage(loaded.image) } else { showText("(图片数据不可用)") }
            }
        case .file:
            let paths = PanelFormat.paths(of: item)
            if PanelFormat.allImageFiles(item), let first = paths.first,
               let loaded = image(key: "file:\(first)", load: { try? Data(contentsOf: URL(fileURLWithPath: first)) }) {
                let size = Self.pixelSize(loaded.image)
                setHeader(PanelFormat.previewHeader(item, appName: appName, now: now, firstImageSize: size))
                if !sameItem { showImage(loaded.image) }
            } else {
                setHeader(PanelFormat.previewHeader(item, appName: appName, now: now))
                if !sameItem { showText(PanelFormat.previewText(paths.joined(separator: "\n")).text) }
            }
        }
    }

    private func image(key: String, load: () -> Data?) -> (image: NSImage, bytes: Int)? {
        if let cachedImage, cachedImage.key == key { return (cachedImage.image, cachedImage.bytes) }
        guard let data = load(), let image = NSImage(data: data) else { return nil }
        cachedImage = (key, image, data.count)
        return (image, data.count)
    }

    private static func pixelSize(_ image: NSImage) -> (width: Int, height: Int)? {
        guard let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    private func setHeader(_ header: PanelFormat.PreviewHeader) {
        let normal: [NSAttributedString.Key: Any] = [.font: Theme.subtitleFont, .foregroundColor: Theme.textTertiary]
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                                    .foregroundColor: Theme.textEmphasis]
        let result = NSMutableAttributedString(string: header.title, attributes: title)
        for (i, part) in header.parts.enumerated() {
            result.append(NSAttributedString(string: i == 0 ? "  " : "  ·  ", attributes: normal))
            result.append(NSAttributedString(string: part, attributes: normal))
        }
        headerField.attributedStringValue = result
    }

    private func showText(_ text: String) {
        imageScroll.isHidden = true
        imageView.image = nil
        textScroll.isHidden = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Theme.previewLineHeight
        paragraph.maximumLineHeight = Theme.previewLineHeight
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: Theme.previewFont, .foregroundColor: Theme.previewText, .paragraphStyle: paragraph,
        ]))
        textView.scroll(.zero)
    }

    private func showImage(_ image: NSImage) {
        textScroll.isHidden = true
        imageScroll.isHidden = false
        imageScroll.magnification = 1
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: imageScroll.contentSize)
    }
}

/// 缩小到比可视区域小时让图片居中。
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let doc = documentView.frame
        if rect.width > doc.width { rect.origin.x = (doc.width - rect.width) / 2 }
        if rect.height > doc.height { rect.origin.y = (doc.height - rect.height) / 2 }
        return rect
    }
}
