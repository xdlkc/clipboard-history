import XCTest
@testable import ClipboardCore

final class FrontmostTrackerTests: XCTestCase {
    func testKeepsLastExternalAppAndIgnoresSelf() {
        var tracker = FrontmostTracker<String>()
        XCTAssertNil(tracker.lastExternal)
        tracker.didActivate("Self", isSelf: true)
        XCTAssertNil(tracker.lastExternal)
        tracker.didActivate("Safari", isSelf: false)
        tracker.didActivate("TextEdit", isSelf: false)
        XCTAssertEqual(tracker.lastExternal, "TextEdit")
    }

    /// 审查场景:关掉本应用的弹窗后立刻唤出面板,应粘贴回最近的其他应用,而不是更早的那个。
    func testSelfActivationAfterDialogDoesNotRevertToStaleApp() {
        var tracker = FrontmostTracker<String>(initial: "Finder")
        tracker.didActivate("Notes", isSelf: false)
        tracker.didActivate("Self", isSelf: true)
        tracker.didActivate("TextEdit", isSelf: false)
        tracker.didActivate("Self", isSelf: true)
        XCTAssertEqual(tracker.lastExternal, "TextEdit")
    }
}
