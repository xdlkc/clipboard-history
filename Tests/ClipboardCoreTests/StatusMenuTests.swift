import XCTest
@testable import ClipboardCore

final class StatusMenuTests: XCTestCase {
    func testLayoutAndTitles() {
        XCTAssertEqual(StatusMenu.layout.map { $0?.title ?? "-" },
                       ["打开面板", "-", "登录自启", "辅助功能设置", "-", "清空未固定历史…", "-", "退出"])
    }

    func testAccessibilityDeepLink() {
        XCTAssertEqual(StatusMenu.accessibilitySettingsURL.scheme, "x-apple.systempreferences")
        XCTAssertTrue(StatusMenu.accessibilitySettingsURL.absoluteString.hasSuffix("?Privacy_Accessibility"))
    }

    func testLoginItemCheckState() {
        XCTAssertEqual(StatusMenu.checkState(for: .enabled), .on)
        XCTAssertEqual(StatusMenu.checkState(for: .requiresApproval), .mixed)
        XCTAssertEqual(StatusMenu.checkState(for: .notRegistered), .off)
        XCTAssertEqual(StatusMenu.checkState(for: .notFound), .off)
    }

    func testLoginItemToggleDirection() {
        XCTAssertTrue(StatusMenu.shouldRegister(currentStatus: .notRegistered))
        XCTAssertTrue(StatusMenu.shouldRegister(currentStatus: .notFound))
        XCTAssertFalse(StatusMenu.shouldRegister(currentStatus: .enabled))
        XCTAssertFalse(StatusMenu.shouldRegister(currentStatus: .requiresApproval))
    }

    func testLoginItemFailureMentionsApplicationsFolder() {
        let alert = StatusMenu.loginItemFailedAlert(register: true, error: "Operation not permitted")
        XCTAssertEqual(alert.message, "无法开启登录自启")
        XCTAssertTrue(alert.informative.contains("/Applications"))
        XCTAssertTrue(alert.informative.contains("Operation not permitted"))
        XCTAssertEqual(StatusMenu.loginItemFailedAlert(register: false, error: "").message, "无法关闭登录自启")
    }

    func testHotkeyUnavailableNotice() {
        let hotkey = HotkeyConfig.default
        XCTAssertEqual(StatusMenu.openPanelTitle(hotkey: hotkey, registered: true), "打开面板")
        XCTAssertEqual(StatusMenu.openPanelTitle(hotkey: hotkey, registered: false), "打开面板(⚠️ ⌘⌥C 不可用)")
        let alert = StatusMenu.hotkeyUnavailableAlert(hotkey)
        XCTAssertEqual(alert.message, "全局快捷键 ⌘⌥C 不可用")
        XCTAssertTrue(alert.informative.contains("其他应用占用"))
        XCTAssertTrue(alert.informative.contains("打开面板"))
        XCTAssertEqual(alert.buttons, ["好"])
    }

    func testClearAndAccessibilityAlerts() {
        XCTAssertTrue(StatusMenu.clearUnpinnedAlert.informative.contains("固定的条目会保留"))
        XCTAssertEqual(StatusMenu.clearUnpinnedAlert.buttons, ["清空", "取消"])
        XCTAssertTrue(StatusMenu.accessibilityAlert.informative.contains("已复制"))
        XCTAssertEqual(StatusMenu.accessibilityAlert.buttons.first, "打开系统设置")
    }
}
