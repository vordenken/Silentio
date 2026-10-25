Feature: Safe speaker protection
  Silentio prevents unwanted playback through the internal speakers
  without changing headphones or players that are already paused.

  Scenario: Pause VLC without starting playback
    Given VLC is running and playing media
    When the default output switches to the internal speakers
    Then Silentio pauses VLC with the state-dependent play command
    But a VLC instance that is already paused stays paused
    And a player that has quit in the meantime is not launched

  Scenario: Shared headphone and speaker output
    Given Silentio has muted the internal speakers
    When the same device output powers headphones after they are plugged in
    Then restoring changes neither the headphone volume nor its mute state
    And the previous speaker state is kept for a safe restoration

  Scenario: Waking up during setup
    Given the initial setup has not been completed yet
    When the Mac wakes from sleep
    Then Silentio does not change the speakers

  Scenario: Invalid delay
    When an invalid delay is stored or set at runtime
    Then Silentio uses a finite value between 0 and 5 seconds
    And the correction is logged
