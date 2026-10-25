import AppKit
import Foundation
import os

/// Base class for players that are paused through Apple events.
nonisolated class AppleScriptPlayer: PlayerController {
    private static let logger = Logger(subsystem: "com.vd.Silentio", category: "Automation")

    let bundleIdentifier: String
    let displayName: String
    init(bundleIdentifier: String, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }

    @MainActor var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == bundleIdentifier
        }
    }

    var pauseScript: String {
        """
        if application id "\(bundleIdentifier)" is running then
            tell application id "\(bundleIdentifier)"
                if player state is playing then pause
            end tell
        end if
        """
    }

    func pause() -> String? {
        Self.execute(script: pauseScript, displayName: displayName)
    }

    static func execute(script: String, displayName: String) -> String? {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        guard let appleScript else {
            logger.error("Could not prepare pause command for \(displayName, privacy: .public)")
            return "Could not prepare the AppleScript command."
        }
        appleScript.executeAndReturnError(&error)

        if let error {
            logger.error("Failed to pause \(displayName, privacy: .public): \(error)")
            if error["NSAppleScriptErrorNumber"] as? Int == -1743 {
                return
                    "Allow Silentio to control \(displayName) in System Settings → Privacy & Security → Automation."
            }
            let detail =
                error["NSAppleScriptErrorMessage"] as? String ?? "The player did not respond."
            return "Could not pause \(displayName): \(detail)"
        }
        return nil
    }
}
