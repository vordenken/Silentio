import AppKit
import SwiftUI

/// Provides the app icon for display in the UI.
@MainActor
enum AppIcon {
    /// Loads the app icon directly from the bundle's `.icns` file.
    /// `NSApplication.shared.applicationIconImage` returns a generic icon for
    /// LSUIElement (menu bar) apps, so we load the `.icns` from the bundle instead.
    static var image: NSImage {
        // Try loading the .icns directly from the bundle resources.
        if let icnsPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
            let icon = NSImage(contentsOfFile: icnsPath)
        {
            return icon
        }
        // Fallback to the workspace icon.
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        if icon.isValid {
            return icon
        }
        return NSApplication.shared.applicationIconImage
    }
}
