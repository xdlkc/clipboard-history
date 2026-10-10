import AppKit

/// 颜色与字体,取自主面板设计稿(design/panel.html)。
enum Theme {
    static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    static let panelTop = rgba(44, 44, 50, 0.94)
    static let panelBottom = rgba(30, 30, 35, 0.95)
    static let panelBorder = rgba(255, 255, 255, 0.10)
    static let cornerRadius: CGFloat = 14

    static let textPrimary = rgba(0xEC, 0xEC, 0xEE)
    static let textSecondary = rgba(235, 235, 245, 0.55)
    static let textSecondarySelected = rgba(255, 255, 255, 0.75)
    static let textTertiary = rgba(235, 235, 245, 0.5)
    static let textCount = rgba(235, 235, 245, 0.45)
    static let textEmphasis = rgba(235, 235, 245, 0.8)
    static let iconTint = rgba(235, 235, 245, 0.7)

    static let searchBackground = rgba(255, 255, 255, 0.07)
    static let caret = rgba(0x0A, 0x84, 0xFF)
    static let selection = rgba(0x0A, 0x84, 0xFF, 0.55)
    static let highlightBackground = rgba(0xFF, 0xD6, 0x0A)
    static let highlightText = NSColor.black
    static let pin = rgba(0xFF, 0xD6, 0x0A)
    static let folder = rgba(0x5A, 0xC8, 0xFA)
    static let divider = rgba(255, 255, 255, 0.08)

    static let previewBackground = rgba(0, 0, 0, 0.22)
    static let previewText = rgba(0xD8, 0xD8, 0xDC)

    static let statusBackground = rgba(0, 0, 0, 0.12)
    static let statusBorder = rgba(255, 255, 255, 0.07)
    static let keyCapBackground = rgba(255, 255, 255, 0.10)

    static let searchFont = NSFont.systemFont(ofSize: 24)
    static let titleFont = NSFont.systemFont(ofSize: 13)
    static let titleHighlightFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let subtitleFont = NSFont.systemFont(ofSize: 11)
    static let previewFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let previewLineHeight: CGFloat = 17
}
