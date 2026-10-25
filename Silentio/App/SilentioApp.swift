import AppKit

/// AppKit owns the persistent status item and application lifecycle.
@main
@MainActor
enum SilentioApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
