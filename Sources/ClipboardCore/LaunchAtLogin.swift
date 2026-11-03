import Foundation

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    /// 已请求自启不代表已获系统批准。
    public var isRequested: Bool {
        self == .enabled || self == .requiresApproval
    }
}

/// 系统适配接口;测试使用替身,不会修改机器的登录项。
public protocol LaunchAtLoginService {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
}

/// 登录项由 macOS 持久化,UserDefaults 保存最近同步的注册配置。
/// 系统设置是最终依据;启动/刷新只读取状态,不自动重新注册。
public final class LaunchAtLoginController {
    public static let preferenceKey = "launchAtLoginEnabled"

    private let service: any LaunchAtLoginService
    private let defaults: UserDefaults

    public init(service: any LaunchAtLoginService, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        refresh()
    }

    public var status: LaunchAtLoginStatus { service.status }

    /// 包括等待批准的开启请求;实际能否自启应读取 status。
    public var savedEnabled: Bool { defaults.bool(forKey: Self.preferenceKey) }

    @discardableResult
    public func refresh() -> LaunchAtLoginStatus {
        let current = status
        defaults.set(current.isRequested, forKey: Self.preferenceKey)
        return current
    }

    /// 幂等设置;系统操作失败时抛出错误,不保存未成功的请求。
    public func setEnabled(_ enabled: Bool) throws {
        if enabled != status.isRequested {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        }
        refresh()
    }
}
