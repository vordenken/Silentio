import AppKit
import ServiceManagement
import SwiftUI
import os

/// App delegate: starts audio monitoring and wake monitoring.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger = Logger(subsystem: "com.vd.Silentio", category: "Application")

    private let monitor: any AudioMonitoring
    private let muter: DeviceMuter
    private let settings: SilentioSettings
    private let players: PlayerRegistry
    private var pendingMute: DispatchWorkItem?
    private var muteGeneration: UInt64 = 0

    /// Strong reference to the onboarding window so it isn't released by ARC.
    private var onboardingWindow: NSWindow?
    private var statusController: StatusItemController?
    private var settingsWindow: NSWindow?
    private var settingsOpenRequested = false
    private var settingsCloseTask: Task<Void, Never>?

    override convenience init() {
        self.init(
            monitor: AudioDeviceMonitor.shared, muter: DeviceMuter(),
            settings: .shared, players: .shared)
    }

    init(
        monitor: any AudioMonitoring, muter: DeviceMuter,
        settings: SilentioSettings, players: PlayerRegistry
    ) {
        self.monitor = monitor
        self.muter = muter
        self.settings = settings
        self.players = players
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        installMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(
            monitor: monitor,
            settings: settings,
            openSettings: { [weak self] in self?.showSettings() },
            setMonitoringEnabled: { [weak self] in self?.setMonitoringEnabled($0) }
        )
        #if DEBUG
            let isUITesting = ProcessInfo.processInfo.environment["SILENTIO_UI_TESTING"] == "1"
            let environment = ProcessInfo.processInfo.environment
            // XCTest injects its configuration path into hosted test runs, even without the scheme variable.
            let isUnitTesting =
                (environment["SILENTIO_UNIT_TESTING"] == "1"
                    || environment["XCTestConfigurationFilePath"] != nil)
                && !isUITesting
        #else
            let isUITesting = false
            let isUnitTesting = false
        #endif
        if isUITesting {
            #if DEBUG
                DistributedNotificationCenter.default().addObserver(
                    self,
                    selector: #selector(openSettingsForUITest),
                    name: Notification.Name("com.vd.Silentio.UITest.OpenSettings"),
                    object: nil,
                    suspensionBehavior: .deliverImmediately
                )
            #endif
        } else if !isUnitTesting {
            setupUpdates()
            setupMonitoring()
            setupWakeMonitoring()
            setupLaunchAtLogin()
            muteIfMonitoringStarts()
        }
        if !isUnitTesting { showOnboardingIfNeeded() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsCloseTask?.cancel()
        pendingMute?.cancel()
        monitor.stopMonitoring()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        #if DEBUG
            DistributedNotificationCenter.default().removeObserver(self)
        #endif
    }

    /// Keep the app running (menu bar) even when all windows are closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Open the settings window when the user clicks the Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        if let onboardingWindow, onboardingWindow.isVisible {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showSettings()
        }
        return false
    }

    /// Brings the app forward before opening or reusing its settings window.
    @objc func showSettings() {
        guard !settingsOpenRequested else { return }
        settingsOpenRequested = true
        settingsCloseTask?.cancel()
        settingsCloseTask = nil
        NSApp.setActivationPolicy(.regular)

        // Finish tracking the status item menu before presenting a new window.
        DispatchQueue.main.async { [weak self] in
            self?.presentSettingsWindow()
        }
    }

    private func presentSettingsWindow() {
        guard settingsOpenRequested else { return }
        if settingsWindow == nil {
            let window = NSWindow(
                contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Settings"
            window.titleVisibility = .hidden
            window.setContentSize(NSSize(width: 440, height: 580))
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.identifier = NSUserInterfaceItemIdentifier("silentio.settings")
            window.delegate = self
            window.center()
            settingsWindow = window
        }

        settingsWindow?.deminiaturize(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        settingsOpenRequested = false
    }

    private func settingsDidClose() {
        settingsOpenRequested = false
        settingsCloseTask?.cancel()
        settingsCloseTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self,
                self.onboardingWindow?.isVisible != true
            else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Silentio")

        let settingsItem = appMenu.addItem(
            withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())

        let updatesItem = appMenu.addItem(
            withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        appMenu.addItem(.separator())

        let quitItem = appMenu.addItem(
            withTitle: "Quit Silentio", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quitItem.target = NSApp
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func checkForUpdates() {
        UpdateController.shared.checkForUpdates()
    }

    private func setupUpdates() {
        let updates = UpdateController.shared
        updates.onAvailabilityChange = { [weak self] updateAvailable in
            self?.statusController?.updateIcon(updateAvailable: updateAvailable)
        }
        updates.start()
        #if DEBUG
            // Simulates a gentle reminder so the menu item and icon dot can be reviewed
            // without publishing a newer release to the appcast.
            if CommandLine.arguments.contains("--preview-update-reminder") {
                updates.availableUpdateVersion = "9.9.9"
            }
        #endif
    }

    #if DEBUG
        @objc private func openSettingsForUITest(_ notification: Notification) {
            showSettings()
        }
    #endif

    // MARK: - Onboarding

    private func showOnboardingIfNeeded() {
        if settings.hasCompletedOnboarding {
            // Onboarding already done – run as a menu bar (accessory) app.
            NSApp.setActivationPolicy(.accessory)
            return
        }

        // First launch – show the Dock icon so the onboarding window is visible.
        NSApp.setActivationPolicy(.regular)

        // Open the onboarding window directly on first launch.
        DispatchQueue.main.async { [self] in
            let hostingController = NSHostingController(
                rootView: OnboardingView(onFinish: { [weak self] in
                    self?.onboardingWindow?.close()
                }))
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Welcome to Silentio"
            window.setContentSize(hostingController.view.fittingSize)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.makeKeyAndOrderFront(nil)
            self.onboardingWindow = window
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// When the onboarding window is closed, switch to menu bar (accessory) mode.
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === onboardingWindow {
            settings.hasCompletedOnboarding = true
            onboardingWindow = nil
            if settingsWindow?.isVisible != true { settingsDidClose() }
        } else if notification.object as? NSWindow === settingsWindow {
            // Keep the window for reuse so only one settings window can ever exist.
            settingsDidClose()
        }
    }

    // MARK: - Monitoring

    func setupMonitoring() {
        monitor.onDeviceChange = { [weak self] change in
            self?.handle(change)
        }
        monitor.startMonitoring()
    }

    private func handle(_ change: AudioDeviceMonitor.DeviceChange) {
        guard settings.hasCompletedOnboarding, settings.isMonitoringEnabled else { return }
        switch change {
        case .speakersActivated:
            handleSpeakerActivation()
        case .speakersDeactivated:
            handleSpeakerDeactivation()
        case .otherOutputChanged:
            break
        }
        if settings.shouldPausePlayers(for: change) {
            players.pauseAllEnabled()
        }
    }

    /// Enables or disables reacting to output changes, like Relax's menu toggle.
    func setMonitoringEnabled(_ enabled: Bool) {
        guard settings.isMonitoringEnabled != enabled else { return }
        settings.isMonitoringEnabled = enabled
        if enabled {
            muteIfMonitoringStarts()
        } else {
            muteGeneration &+= 1
            pendingMute?.cancel()
            pendingMute = nil
        }
    }

    private func muteIfMonitoringStarts() {
        guard settings.shouldMuteWhenMonitoringStarts else { return }
        monitor.refreshCurrentDevice()
        guard let device = monitor.currentDevice, device.isBuiltInSpeaker else { return }
        muter.muteBuiltInSpeakers(device)
    }

    private func handleSpeakerActivation() {
        muteGeneration &+= 1
        pendingMute?.cancel()
        pendingMute = nil
        if settings.muteOnDisconnect {
            if let device = monitor.currentDevice, device.isBuiltInSpeaker {
                let generation = muteGeneration
                let action = DispatchWorkItem { [weak self] in
                    guard let self, self.muteGeneration == generation else { return }
                    defer { self.pendingMute = nil }
                    guard self.muteIfSpeakersStillActive(device) else { return }
                    // macOS may restore the speaker's saved mute state while it
                    // finishes the route change, so verify the mute briefly.
                    for delay in Self.muteVerificationDelays {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                            guard let self, self.muteGeneration == generation else { return }
                            self.muteIfSpeakersStillActive(device)
                        }
                    }
                }
                pendingMute = action
                if settings.muteDelay > 0 {
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + settings.muteDelay, execute: action)
                } else {
                    action.perform()
                }
            }
        }

    }

    private static let muteVerificationDelays: [TimeInterval] = [0.3, 1.0]

    @discardableResult
    private func muteIfSpeakersStillActive(_ device: AudioDevice) -> Bool {
        guard settings.muteOnDisconnect,
            let current = monitor.currentDevice,
            current.isBuiltInSpeaker,
            current.uid == device.uid
        else { return false }
        muter.muteBuiltInSpeakers(current)
        return true
    }

    private func handleSpeakerDeactivation() {
        muteGeneration &+= 1
        pendingMute?.cancel()
        pendingMute = nil
        if settings.unmuteOnReconnect {
            muter.restoreBuiltInSpeakers()
        }
    }

    // MARK: - Wake monitoring

    private func setupWakeMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    /// Called when the Mac wakes from sleep (e.g. after closing/opening the lid).
    @objc private func systemDidWake(_ notification: Notification) {
        guard settings.shouldMuteOnWake else { return }
        guard let device = AudioDeviceMonitor.currentDefaultOutputDevice(), device.isBuiltInSpeaker
        else { return }
        muter.muteBuiltInSpeakers(device)
    }

    // MARK: - Launch at login

    private func setupLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            // Apply the persisted setting on launch.
            applyLaunchAtLogin(settings.launchAtLogin, openSettingsOnApproval: false)
        }
    }

    /// Registers or unregisters the app to launch at login via `SMAppService`.
    ///
    /// This is the modern, Apple-recommended API. If the app is not yet approved,
    /// the status becomes `.requiresApproval` and the
    /// user must confirm in System Settings → General → Login Items.
    @available(macOS 13.0, *)
    func applyLaunchAtLogin(_ enabled: Bool, openSettingsOnApproval: Bool = true) {
        do {
            if enabled {
                switch SMAppService.mainApp.status {
                case .enabled:
                    break  // Already registered.
                case .requiresApproval:
                    if openSettingsOnApproval { openLoginItemsSettings() }
                default:
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            logger.error(
                "Failed to update launch at login; check System Settings > General > Login Items: \(error)"
            )
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    /// Opens the Login Items pane in System Settings.
    @available(macOS 13.0, *)
    private func openLoginItemsSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        {
            NSWorkspace.shared.open(url)
        }
    }

    /// Called by the settings view when the launch-at-login toggle changes.
    func launchAtLoginDidChange(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            applyLaunchAtLogin(enabled)
        }
    }
}
