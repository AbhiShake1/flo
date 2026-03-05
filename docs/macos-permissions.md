# macOS Permission Requirements

The macOS app package lives in `apps/macos`. Root `./scripts/*` commands are compatibility wrappers that forward to `apps/macos/scripts/*`.

For production app bundles, ensure the final app target includes these usage descriptions:

- `NSMicrophoneUsageDescription`: explain why dictation needs microphone access.
- `NSSpeechRecognitionUsageDescription`: required for live streaming transcript while speaking.

Accessibility and Input Monitoring do not use Info.plist usage keys; they rely on system privacy prompts/checklists and app guidance.

When packaging with Xcode, verify the generated app contains the correct permission string before notarization.

## Common Dev Gotcha

If you run from transient binaries during development, macOS Privacy panes may not show a stable `flo` entry.

Preferred local flow:

1. Build and launch the bundle (`FloApp.app`) from Finder.
   - easiest: `./scripts/run_dev_app_bundle.sh`
   - default install location: `~/Applications/FloApp.app`
   - for persistent privacy grants across rebuilds, sign with a stable identity via `FLO_CODESIGN_IDENTITY` (Apple Development preferred)
   - once permissions are granted, launch with `./scripts/run_dev_app_bundle.sh --open-only` to avoid rebuild/re-sign churn
2. In-app, trigger permission prompts:
   - Microphone: press "Request Microphone"
   - Accessibility/Input Monitoring: press "Open Settings" in each row (this now triggers prompt APIs first)
3. Reopen System Settings Privacy panes and enable `FloApp`.
