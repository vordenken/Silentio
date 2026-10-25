import Combine
import Foundation
import Sparkle

/// The part of Sparkle's updater that Silentio's settings use; tests substitute a fake.
protocol Updater: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var scheduledUpdateHandler: ((String?) -> Void)? { get set }
    func checkForUpdates()
    func resetUpdateCycleAfterShortDelay()
}

/// Update preferences shown in settings and onboarding, mirrored from the updater so SwiftUI observes them.
final class UpdateController: ObservableObject {
    static let betaDefaultsKey = "BetaUpdatesEnabled"
    static let shared = UpdateController(updater: SparkleUpdater(startingUpdater: false))

    private let updater: any Updater
    private let defaults: UserDefaults
    var onAvailabilityChange: ((Bool) -> Void)?

    /// Version found by a background check that Sparkle shows as a gentle reminder.
    @Published var availableUpdateVersion: String? {
        didSet {
            guard oldValue != availableUpdateVersion else { return }
            onAvailabilityChange?(availableUpdateVersion != nil)
        }
    }

    @Published var automaticallyChecks: Bool {
        didSet {
            updater.automaticallyChecksForUpdates = automaticallyChecks
            // Downloading without checking is impossible, so turning checks off also stops downloads.
            if !automaticallyChecks && automaticallyDownloads { automaticallyDownloads = false }
        }
    }

    @Published var automaticallyDownloads: Bool {
        didSet {
            if automaticallyDownloads && !automaticallyChecks { automaticallyChecks = true }
            updater.automaticallyDownloadsUpdates = automaticallyDownloads
        }
    }

    @Published var betaUpdates: Bool {
        didSet {
            defaults.set(betaUpdates, forKey: Self.betaDefaultsKey)
            updater.resetUpdateCycleAfterShortDelay()
        }
    }

    init(updater: any Updater, defaults: UserDefaults = .standard) {
        self.updater = updater
        self.defaults = defaults
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
        betaUpdates = defaults.bool(forKey: Self.betaDefaultsKey)
        updater.scheduledUpdateHandler = { [weak self] version in
            self?.availableUpdateVersion = version
        }
    }

    /// Starts scheduled update checks; the unit-test host never calls this.
    func start() {
        (updater as? SparkleUpdater)?.startUpdater()
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    static func allowedChannels(defaults: UserDefaults) -> Set<String> {
        defaults.bool(forKey: betaDefaultsKey) ? ["beta"] : []
    }
}

/// Sparkle-backed updater. The feed URL and public EdDSA key come from Info.plist.
final class SparkleUpdater: NSObject, Updater, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private let defaults: UserDefaults
    private var controller: SPUStandardUpdaterController?

    var scheduledUpdateHandler: ((String?) -> Void)?

    init(defaults: UserDefaults = .standard, startingUpdater: Bool = true) {
        self.defaults = defaults
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater, updaterDelegate: self, userDriverDelegate: self)
    }

    private var updater: SPUUpdater? { controller?.updater }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set { updater?.automaticallyDownloadsUpdates = newValue }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    func startUpdater() {
        controller?.startUpdater()
    }

    func resetUpdateCycleAfterShortDelay() {
        updater?.resetUpdateCycleAfterShortDelay()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UpdateController.allowedChannels(defaults: defaults)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        scheduledUpdateHandler?(handleShowingUpdate ? nil : update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        scheduledUpdateHandler?(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        scheduledUpdateHandler?(nil)
    }
}
