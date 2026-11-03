import Foundation
import XCTest
@testable import ClipboardCore

final class LaunchAtLoginTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var service: FakeLoginService!

    override func setUp() {
        super.setUp()
        suiteName = "ClipboardHistory.LaunchAtLoginTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        service = FakeLoginService()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        service = nil
        super.tearDown()
    }

    private func makeController() -> LaunchAtLoginController {
        LaunchAtLoginController(service: service, defaults: defaults)
    }

    func testFreshInstallDefaultsToOffWithoutRegistering() {
        let controller = makeController()
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertFalse(controller.savedEnabled)
        XCTAssertEqual(service.operations, [])
    }

    func testEnableAndDisablePersistAcrossControllerInstances() throws {
        let controller = makeController()
        try controller.setEnabled(true)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertTrue(controller.savedEnabled)
        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertTrue(reopenedDefaults.bool(forKey: LaunchAtLoginController.preferenceKey))
        let reopened = LaunchAtLoginController(service: service, defaults: reopenedDefaults)
        XCTAssertTrue(reopened.savedEnabled)
        XCTAssertEqual(service.operations, ["register"])
        try reopened.setEnabled(false)
        XCTAssertEqual(reopened.status, .notRegistered)
        XCTAssertFalse(reopened.savedEnabled)
        XCTAssertFalse(makeController().savedEnabled)
        XCTAssertEqual(service.operations, ["register", "unregister"])
    }

    func testRepeatedRequestsAreIdempotent() throws {
        let controller = makeController()
        try controller.setEnabled(false)
        try controller.setEnabled(true)
        try controller.setEnabled(true)
        try controller.setEnabled(false)
        try controller.setEnabled(false)
        XCTAssertEqual(service.operations, ["register", "unregister"])
    }

    func testPendingApprovalIsPersistedButNotShownAsEnabledAndCanBeCancelled() throws {
        service.registrationStatus = .requiresApproval
        let controller = makeController()
        try controller.setEnabled(true)
        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertTrue(controller.savedEnabled)
        XCTAssertEqual(StatusMenu.checkState(for: controller.status), .mixed)
        try controller.setEnabled(true)
        XCTAssertEqual(service.operations, ["register"])
        try controller.setEnabled(false)
        XCTAssertFalse(controller.savedEnabled)
        XCTAssertEqual(service.operations, ["register", "unregister"])
    }

    func testRegisterFailureDoesNotPersistEnabled() {
        let controller = makeController()
        service.shouldFail = true
        XCTAssertThrowsError(try controller.setEnabled(true))
        XCTAssertFalse(controller.savedEnabled)
        XCTAssertEqual(controller.status, .notRegistered)
    }

    func testUnregisterFailurePreservesEnabledPreference() {
        service.status = .enabled
        let controller = makeController()
        service.shouldFail = true
        XCTAssertThrowsError(try controller.setEnabled(false))
        XCTAssertTrue(controller.savedEnabled)
        XCTAssertEqual(controller.status, .enabled)
    }

    func testExistingSystemRegistrationIsAdoptedWithoutRegisteringAgain() {
        for status: LaunchAtLoginStatus in [.enabled, .requiresApproval] {
            service.status = status
            let controller = makeController()
            XCTAssertEqual(controller.status, status)
            XCTAssertTrue(controller.savedEnabled)
        }
        XCTAssertEqual(service.operations, [])
    }

    func testStaleSavedPreferenceNeverOverridesSystemOnStartup() {
        for status: LaunchAtLoginStatus in [.notRegistered, .notFound, .requiresApproval] {
            defaults.set(true, forKey: LaunchAtLoginController.preferenceKey)
            service.status = status
            let controller = makeController()
            XCTAssertEqual(controller.status, status)
            XCTAssertEqual(controller.savedEnabled, status.isRequested)
        }
        XCTAssertEqual(service.operations, [])
    }

    func testExternalSystemChangesAreReflectedOnRefresh() {
        let controller = makeController()
        for status: LaunchAtLoginStatus in [.enabled, .requiresApproval, .notRegistered, .notFound] {
            service.status = status
            XCTAssertEqual(controller.refresh(), status)
            XCTAssertEqual(controller.savedEnabled, status.isRequested)
        }
        XCTAssertEqual(service.operations, [])
    }

    func testNotFoundCanRetryRegistration() throws {
        service.status = .notFound
        let controller = makeController()
        try controller.setEnabled(true)
        XCTAssertTrue(controller.savedEnabled)
        XCTAssertEqual(service.operations, ["register"])
    }

    func testApprovalAlertOffersSystemSettings() {
        XCTAssertTrue(StatusMenu.loginItemApprovalAlert.informative.contains("批准前"))
        XCTAssertEqual(StatusMenu.loginItemApprovalAlert.buttons, ["打开系统设置", "稍后"])
    }
}

private final class FakeLoginService: LaunchAtLoginService {
    enum Failure: Error { case denied }
    var status: LaunchAtLoginStatus = .notRegistered
    var registrationStatus: LaunchAtLoginStatus = .enabled
    var operations: [String] = []
    var shouldFail = false

    func register() throws {
        operations.append("register")
        if shouldFail { throw Failure.denied }
        status = registrationStatus
    }

    func unregister() throws {
        operations.append("unregister")
        if shouldFail { throw Failure.denied }
        status = .notRegistered
    }
}
