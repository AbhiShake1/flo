# P06 Shortcut and Input Monitoring Spec

## Shortcuts
- Default dictation shortcut: hold `⌥Space`.
- Default read-aloud shortcut: press `⌥R`.
- Both shortcuts configurable by user.

## Event Semantics
- Dictation trigger is edge-based:
  - keyDown with matching combo starts capture (if not active).
  - keyUp of trigger key stops capture.
- Read action is keyDown single-shot debounce.

## Input Monitoring
- Use global event taps/monitors.
- Detect key conflicts during configuration and block duplicates.

## Persistence
- Save `ShortcutBinding` values in UserDefaults.
- Load on launch and activate runtime listeners.
