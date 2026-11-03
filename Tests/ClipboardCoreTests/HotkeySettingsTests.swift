import XCTest
@testable import ClipboardCore

final class HotkeySettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "HotkeySettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private var custom: HotkeyConfig {
        HotkeyConfig(keyCode: 9, modifiers: [.control, .shift], key: "v")
    }

    func testDefaultAndAllSupportedKeys() throws {
        XCTAssertEqual(HotkeySettings(defaults: defaults).current, .default)
        XCTAssertEqual(Set(HotkeyConfig.supportedKeys.map { $0.code }).count, 36)
        for key in HotkeyConfig.supportedKeys {
            try HotkeyConfig(keyCode: key.code, modifiers: [.option], key: key.key).validate()
        }
        try HotkeyConfig.default.validate()
    }

    func testInvalidModifiersAndKeys() {
        let invalidFlags: [HotkeyConfig.Modifiers] = [[], [.shift], .init(rawValue: 0x4000 | 0x100)]
        for flags in invalidFlags {
            XCTAssertThrowsError(try HotkeyConfig(keyCode: 8, modifiers: flags, key: "c").validate())
        }
        for config in [
            HotkeyConfig(keyCode: 9, modifiers: [.command], key: "c"),
            HotkeyConfig(keyCode: 8, modifiers: [.command], key: "C"),
            HotkeyConfig(keyCode: 999, modifiers: [.command], key: ""),
        ] {
            XCTAssertThrowsError(try config.validate())
        }
    }

    func testSaveReloadAndReset() throws {
        let settings = HotkeySettings(defaults: defaults)
        var registered: [HotkeyConfig] = []
        try settings.update(custom) { registered.append($0); return true }
        XCTAssertEqual(registered, [custom])
        XCTAssertEqual(settings.current, custom)
        XCTAssertEqual(HotkeySettings(defaults: UserDefaults(suiteName: suite)!).current, custom)
        try settings.update(.default) { _ in true }
        XCTAssertEqual(HotkeySettings(defaults: defaults).current, .default)
    }

    func testRegistrationFailureKeepsCurrentAndPersistence() throws {
        let settings = HotkeySettings(defaults: defaults)
        try settings.update(custom) { _ in true }
        let saved = defaults.data(forKey: HotkeySettings.storageKey)
        XCTAssertThrowsError(try settings.update(.default) { _ in false })
        XCTAssertEqual(settings.current, custom)
        XCTAssertEqual(defaults.data(forKey: HotkeySettings.storageKey), saved)
        XCTAssertEqual(HotkeySettings(defaults: defaults).current, custom)
    }

    func testValidationRunsBeforeRegistration() {
        let settings = HotkeySettings(defaults: defaults)
        let invalid = HotkeyConfig(keyCode: 8, modifiers: [], key: "c")
        XCTAssertThrowsError(try settings.update(invalid) { _ in
            XCTFail("Invalid shortcut must not be registered")
            return true
        })
        XCTAssertNil(defaults.object(forKey: HotkeySettings.storageKey))
        XCTAssertEqual(settings.current, .default)
    }

    func testCorruptAndInvalidSavedDataFallBack() throws {
        defaults.set(Data("invalid".utf8), forKey: HotkeySettings.storageKey)
        XCTAssertEqual(HotkeySettings(defaults: defaults).current, .default)
        let invalid = HotkeyConfig(keyCode: 8, modifiers: [.shift], key: "c")
        defaults.set(try JSONEncoder().encode(invalid), forKey: HotkeySettings.storageKey)
        XCTAssertEqual(HotkeySettings(defaults: defaults).current, .default)
    }

    func testSameConfigurationCanRetryRegistration() throws {
        let settings = HotkeySettings(defaults: defaults)
        var calls = 0
        try settings.update(.default) { _ in calls += 1; return true }
        XCTAssertEqual(calls, 1, "启动注册失败后应允许重试同一配置")
    }
}
