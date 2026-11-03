import Foundation

public extension HotkeyConfig {
    /// ANSI 物理键位,与 Carbon 虚拟键码一致。
    static let supportedKeys: [(key: String, code: UInt32)] = [
        ("a", 0), ("b", 11), ("c", 8), ("d", 2), ("e", 14), ("f", 3),
        ("g", 5), ("h", 4), ("i", 34), ("j", 38), ("k", 40), ("l", 37),
        ("m", 46), ("n", 45), ("o", 31), ("p", 35), ("q", 12), ("r", 15),
        ("s", 1), ("t", 17), ("u", 32), ("v", 9), ("w", 13), ("x", 7),
        ("y", 16), ("z", 6), ("0", 29), ("1", 18), ("2", 19), ("3", 20),
        ("4", 21), ("5", 23), ("6", 22), ("7", 26), ("8", 28), ("9", 25),
    ]

    func validate() throws {
        let allowed: Modifiers = [.command, .option, .control, .shift]
        guard modifiers.subtracting(allowed).isEmpty,
              !modifiers.intersection([.command, .option, .control]).isEmpty else {
            throw HotkeySettings.Error.invalidModifiers
        }
        guard Self.supportedKeys.contains(where: { $0.key == key && $0.code == keyCode }) else {
            throw HotkeySettings.Error.invalidKey
        }
    }
}

/// 只有注册成功才更新配置。register 闭包必须在失败时保留原热键。
public final class HotkeySettings {
    public enum Error: LocalizedError {
        case invalidModifiers, invalidKey, unavailable

        public var errorDescription: String? {
            switch self {
            case .invalidModifiers: return "请至少选择 Command、Option 或 Control 中的一个修饰键。"
            case .invalidKey: return "请选择 A–Z 或 0–9 的有效键位。"
            case .unavailable: return "快捷键可能已被其他应用占用，原快捷键和配置已保留。"
            }
        }
    }

    public static let storageKey = "globalHotkey"
    public private(set) var current: HotkeyConfig
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data),
           (try? config.validate()) != nil {
            current = config
        } else {
            current = .default
        }
    }

    public func update(_ config: HotkeyConfig, register: (HotkeyConfig) -> Bool) throws {
        try config.validate()
        let data = try JSONEncoder().encode(config)
        guard register(config) else { throw Error.unavailable }
        defaults.set(data, forKey: Self.storageKey)
        current = config
    }
}
