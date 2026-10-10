import Foundation

/// 记录最近一个激活的「其他」应用(忽略本应用)。粘贴前若本应用处于激活状态,把焦点还给它。
public struct FrontmostTracker<App> {
    public private(set) var lastExternal: App?

    public init(initial: App? = nil) {
        lastExternal = initial
    }

    /// 收到应用激活通知时调用;本应用的激活不覆盖记录。
    public mutating func didActivate(_ app: App, isSelf: Bool) {
        guard !isSelf else { return }
        lastExternal = app
    }
}
