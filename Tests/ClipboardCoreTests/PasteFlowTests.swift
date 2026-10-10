import XCTest
@testable import ClipboardCore

final class PasteFlowTests: XCTestCase {
    private final class Recorder {
        var trusted = true
        var scheduled: [(TimeInterval, () -> Void)] = []
        var posted = 0
        var prompts = 0
        var events: [String] = []
    }

    private func make(_ r: Recorder) -> PasteCoordinator {
        PasteCoordinator(
            isTrusted: { r.trusted },
            schedule: { delay, work in r.events.append("schedule"); r.scheduled.append((delay, work)) },
            postPaste: { r.events.append("post"); r.posted += 1 },
            promptForAccessibility: { r.events.append("prompt"); r.prompts += 1 })
    }

    private func write(_ r: Recorder, _ ok: Bool = true) -> () -> Bool {
        { r.events.append("write"); return ok }
    }

    func testHotkeyDefaultIsCommandOptionC() {
        let config = HotkeyConfig.default
        XCTAssertEqual(config.keyCode, 8)
        XCTAssertEqual(config.modifiers.rawValue, 0x0100 | 0x0800)
        XCTAssertEqual(config.displayString, "⌘⌥C")
        XCTAssertEqual(config.key, "c")
        XCTAssertEqual(HotkeyConfig(keyCode: 9, modifiers: [.control, .shift, .command], key: "v").displayString, "⌘⌃⇧V")
    }

    func testTrustedPasteWritesThenSchedulesCommandVAfter120ms() {
        let r = Recorder()
        let flow = make(r)
        XCTAssertEqual(flow.choose(.paste, write: write(r)), .pasteScheduled)
        XCTAssertEqual(r.events, ["write", "schedule"])
        XCTAssertEqual(r.scheduled.first?.0, 0.12)
        XCTAssertEqual(r.posted, 0, "⌘V 在延时后才发送")
        r.scheduled.first?.1()
        XCTAssertEqual(r.posted, 1)
        XCTAssertEqual(r.events, ["write", "schedule", "post"])
    }

    func testCopyOnlyNeverPastesOrPrompts() {
        let r = Recorder()
        let flow = make(r)
        XCTAssertEqual(flow.choose(.copyOnly, write: write(r)), .copiedOnly)
        r.trusted = false
        XCTAssertEqual(flow.choose(.copyOnly, write: write(r)), .copiedOnly)
        XCTAssertEqual(r.events, ["write", "write"])
        XCTAssertFalse(flow.hasPrompted)
    }

    func testUntrustedCopiesAndPromptsOnlyOnFirstPaste() {
        let r = Recorder()
        r.trusted = false
        let flow = make(r)
        XCTAssertEqual(flow.choose(.paste, write: write(r)), .promptedForAccessibility)
        XCTAssertEqual(flow.choose(.paste, write: write(r)), .copiedWithoutPermission)
        XCTAssertEqual(r.events, ["write", "prompt", "write"], "内容总是先复制")
        XCTAssertEqual(r.prompts, 1)
        XCTAssertEqual(r.posted, 0)
    }

    func testPasteWorksOnceTrustIsGranted() {
        let r = Recorder()
        r.trusted = false
        let flow = make(r)
        flow.choose(.paste, write: write(r))
        r.trusted = true
        XCTAssertEqual(flow.choose(.paste, write: write(r)), .pasteScheduled)
        r.scheduled.forEach { $0.1() }
        XCTAssertEqual(r.posted, 1)
    }

    func testWriteFailureDoesNothingElse() {
        let r = Recorder()
        let flow = make(r)
        XCTAssertEqual(flow.choose(.paste, write: write(r, false)), .writeFailed)
        r.trusted = false
        XCTAssertEqual(flow.choose(.paste, write: write(r, false)), .writeFailed)
        XCTAssertEqual(r.events, ["write", "write"])
        XCTAssertFalse(flow.hasPrompted)
    }
}
