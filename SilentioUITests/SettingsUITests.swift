import AppKit
import XCTest

final class SettingsUITests: XCTestCase {
    @MainActor
    func testFirstLaunchKeepsOnboardingVisible() {
        let application = XCUIApplication()
        application.launchEnvironment["SILENTIO_UI_TESTING"] = "1"
        application.launchArguments = ["-AppleLanguages", "(en)", "-hasCompletedOnboarding", "NO"]
        defer { application.terminate() }
        application.launch()

        XCTAssertTrue(application.windows["Welcome to Silentio"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFrontmostApp("com.vd.Silentio"))
        XCTAssertTrue(application.menuBars.statusItems["silentio.status"].exists)
    }

    @MainActor
    func testStatusItemOpensSettingsAndReopensAfterClosing() {
        let application = XCUIApplication()
        application.launchEnvironment["SILENTIO_UI_TESTING"] = "1"
        application.launchArguments = ["-AppleLanguages", "(en)", "-hasCompletedOnboarding", "YES"]
        defer { application.terminate() }
        application.launch()

        let statusItem = application.menuBars.statusItems["silentio.status"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))

        for _ in 0..<2 {
            statusItem.click()
            let settingsItem = application.menuItems["silentio.status.settings"]
            XCTAssertTrue(settingsItem.waitForExistence(timeout: 5))
            application.typeKey(",", modifierFlags: .command)

            let window = application.windows["silentio.settings"]
            XCTAssertTrue(window.waitForExistence(timeout: 5))
            XCTAssertTrue(window.isHittable)
            XCTAssertTrue(application.staticTexts["Silentio"].exists)
            window.buttons[XCUIIdentifierCloseWindow].click()
            XCTAssertTrue(window.waitForNonExistence(timeout: 5))
        }
    }

    @MainActor
    func testSettingsActivateSilentioWhileFinderIsFrontmost() {
        let application = XCUIApplication()
        application.launchEnvironment["SILENTIO_UI_TESTING"] = "1"
        application.launchArguments = ["-AppleLanguages", "(en)", "-hasCompletedOnboarding", "YES"]
        defer { application.terminate() }
        application.launch()

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        let window = application.windows["silentio.settings"]
        for _ in 0..<2 {
            finder.activate()
            XCTAssertTrue(waitForFrontmostApp("com.apple.finder"))

            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.vd.Silentio.UITest.OpenSettings"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )

            XCTAssertTrue(window.waitForExistence(timeout: 5))
            XCTAssertTrue(
                waitForFrontmostApp("com.vd.Silentio"),
                "Frontmost: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")")
            XCTAssertTrue(window.isHittable)
            window.buttons[XCUIIdentifierCloseWindow].click()
            XCTAssertTrue(window.waitForNonExistence(timeout: 5))
        }
    }

    private func waitForFrontmostApp(_ bundleIdentifier: String) -> Bool {
        for _ in 0..<50 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

}
