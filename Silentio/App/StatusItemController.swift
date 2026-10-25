import AppKit

/// Owns the menu bar item independently of any window.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    let statusItem: NSStatusItem
    private let monitor: any AudioMonitoring
    private let settings: SilentioSettings
    private let openSettings: () -> Void
    private let setMonitoringEnabled: (Bool) -> Void

    init(
        monitor: any AudioMonitoring,
        settings: SilentioSettings,
        openSettings: @escaping () -> Void,
        setMonitoringEnabled: @escaping (Bool) -> Void
    ) {
        self.monitor = monitor
        self.settings = settings
        self.openSettings = openSettings
        self.setMonitoringEnabled = setMonitoringEnabled
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.isVisible = true
        updateIcon(updateAvailable: false)
        statusItem.button?.setAccessibilityIdentifier("silentio.status")
        statusItem.button?.appearsDisabled = !settings.isMonitoringEnabled

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        monitor.refreshCurrentDevice()
        menu.removeAllItems()

        if let version = UpdateController.shared.availableUpdateVersion {
            let update = menu.addItem(
                withTitle: "Version \(version) Is Available…", action: #selector(checkForUpdates),
                keyEquivalent: "")
            update.target = self
            update.image = menuImage(named: "arrow.down.circle.fill")
            menu.addItem(.separator())
        }

        let status = menu.addItem(withTitle: statusTitle, action: nil, keyEquivalent: "")
        status.image = menuImage(
            named: monitor.currentDevice?.isBuiltInSpeaker == true ? "speaker" : "headphones")
        status.isEnabled = false
        menu.addItem(.separator())

        let enabled = settings.isMonitoringEnabled
        let toggle = menu.addItem(
            withTitle: enabled ? "Disable Silentio" : "Enable Silentio",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.image = menuImage(named: enabled ? "pause.circle" : "play.circle")
        toggle.identifier = NSUserInterfaceItemIdentifier("silentio.status.toggle")
        menu.addItem(.separator())

        let settings = menu.addItem(
            withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = menuImage(named: "gearshape")
        settings.identifier = NSUserInterfaceItemIdentifier("silentio.status.settings")

        let updates = menu.addItem(
            withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        updates.image = menuImage(named: "arrow.down.circle")

        menu.addItem(.separator())
        let quit = menu.addItem(
            withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        quit.image = menuImage(named: "power")
    }

    /// Shows a small dot on the menu bar icon while a background update check found a new version.
    func updateIcon(updateAvailable: Bool) {
        statusItem.button?.image = Self.icon(updateAvailable: updateAvailable)
        statusItem.button?.setAccessibilityLabel(
            updateAvailable ? "Silentio, update available" : "Silentio")
    }

    static func icon(updateAvailable: Bool) -> NSImage? {
        guard let base = NSImage(named: "MenuBarIcon") else { return nil }
        guard updateAvailable else { return base }
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.black.set()
            let diameter = rect.width * 0.25
            NSBezierPath(
                ovalIn: NSRect(
                    x: rect.maxX - diameter, y: rect.maxY - diameter, width: diameter,
                    height: diameter
                )
            ).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private var statusTitle: String {
        guard let device = monitor.currentDevice else { return "No output device" }
        return device.isBuiltInSpeaker
            ? "Internal speakers active" : "\(device.name) · Other output active"
    }

    private func menuImage(named symbol: String) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    @objc private func showSettings() { openSettings() }
    @objc private func toggleMonitoring() {
        setMonitoringEnabled(!settings.isMonitoringEnabled)
        statusItem.button?.appearsDisabled = !settings.isMonitoringEnabled
    }
    @objc private func checkForUpdates() { UpdateController.shared.checkForUpdates() }
}
