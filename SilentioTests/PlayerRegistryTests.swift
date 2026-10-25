import Foundation
import Testing

@testable import Silentio

nonisolated private struct ScriptPlayer: PlayerController {
    let bundleIdentifier: String
    let displayName: String
    let isRunning: Bool
    var pauseScript: String { "error \"Synthetic failure\" number -10000" }
    func pause() -> String? {
        Issue.record("The registry must execute scripts on its serial queue")
        return nil
    }
}

@MainActor
struct PlayerRegistryTests {
    @Test(arguments: [true, false], [true, false])
    func onlyEnabledRunningPlayersExecuteScripts(enabled: Bool, running: Bool) async throws {
        let domain = "PlayerRegistryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SilentioSettings(defaults: defaults)
        settings.enabledPlayers = enabled ? ["test.player"] : []
        let registry = PlayerRegistry(
            settings: settings,
            players: [
                ScriptPlayer(
                    bundleIdentifier: "test.player", displayName: "Test Player", isRunning: running)
            ])
        registry.pauseAllEnabled()
        if enabled && running {
            for _ in 0..<200 where registry.lastAutomationError == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(
                registry.lastAutomationError == "Could not pause Test Player: Synthetic failure")
            settings.enabledPlayers = []
            registry.pauseAllEnabled()
            #expect(registry.lastAutomationError == nil)
        } else {
            try await Task.sleep(for: .milliseconds(100))
            #expect(registry.lastAutomationError == nil)
        }
    }
}
