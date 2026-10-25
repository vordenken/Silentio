import AppKit
import XCTest

@testable import Silentio

final class SettingsWindowTests: XCTestCase {
    @MainActor
    func testSettingsWindowIsVisibleAndReopensAfterClosing() async throws {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        var window: NSWindow?
        defer {
            window?.close()
        }

        delegate.showSettings()
        await nextMainQueueTurn()

        window = settingsWindow()
        XCTAssertNotNil(window)
        XCTAssertTrue(window?.isVisible == true)
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertEqual(window?.titleVisibility, .hidden)

        window?.close()
        let firstWindow = window
        let returnedToMenuBar = await waitForActivationPolicy(.accessory)
        XCTAssertTrue(returnedToMenuBar)

        delegate.showSettings()
        await nextMainQueueTurn()

        window = settingsWindow()
        XCTAssertTrue(window?.isVisible == true)
        XCTAssertTrue(window === firstWindow, "Settings must reuse a single window")
        XCTAssertEqual(
            NSApp.windows.filter { $0.identifier?.rawValue == "silentio.settings" }.count, 1)

        window?.close()
        let returnedToMenuBarAgain = await waitForActivationPolicy(.accessory)
        XCTAssertTrue(returnedToMenuBarAgain)
    }

    @MainActor
    private func settingsWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "silentio.settings" && $0.isVisible }
    }

    @MainActor
    func testStatusItemSettingsActionInvokesWindowOpening() {
        var openCount = 0
        var toggledTo: Bool?
        let settings = SilentioSettings(
            defaults: UserDefaults(suiteName: "SettingsWindowTests.\(UUID().uuidString)")!)
        let controller = StatusItemController(
            monitor: AudioDeviceMonitor.shared,
            settings: settings,
            openSettings: { openCount += 1 },
            setMonitoringEnabled: {
                toggledTo = $0
                settings.isMonitoringEnabled = $0
            }
        )
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        XCTAssertTrue(controller.statusItem.isVisible)
        XCTAssertNotNil(controller.statusItem.button?.image)
        let menu = controller.statusItem.menu!
        controller.menuNeedsUpdate(menu)
        let settingsIndex = menu.items.firstIndex {
            $0.identifier?.rawValue == "silentio.status.settings"
        }
        XCTAssertNotNil(settingsIndex)
        menu.performActionForItem(at: settingsIndex!)
        XCTAssertEqual(openCount, 1)

        let toggleIndex = menu.items.firstIndex {
            $0.identifier?.rawValue == "silentio.status.toggle"
        }
        XCTAssertEqual(menu.items[toggleIndex!].title, "Disable Silentio")
        menu.performActionForItem(at: toggleIndex!)
        XCTAssertEqual(toggledTo, false)
        controller.menuNeedsUpdate(menu)
        XCTAssertEqual(
            menu.items.first { $0.identifier?.rawValue == "silentio.status.toggle" }?.title,
            "Enable Silentio")
    }

    @MainActor
    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    @MainActor
    private func waitForActivationPolicy(_ policy: NSApplication.ActivationPolicy) async -> Bool {
        for _ in 0..<50 {
            if NSApp.activationPolicy() == policy { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }
}
