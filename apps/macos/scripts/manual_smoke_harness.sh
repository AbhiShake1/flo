#!/usr/bin/env bash
set -euo pipefail

cat <<'CHECKLIST'
flo manual smoke harness (macOS 15+)

1. Build and launch:
   - ./scripts/run_dev_app_bundle.sh

2. Unauthenticated gate:
   - verify auth-gated shell appears
   - verify settings actions are blocked until login

3. OAuth path:
   - login with ChatGPT OAuth
   - verify state unlocks and menu bar actions are available

4. Permissions/onboarding:
   - verify checklist surfaces Mic/Accessibility/Input Monitoring
   - grant permissions and return focus to app
   - verify status refreshes automatically

5. Dictation:
   - hold Option+Space, speak, release
   - verify floating bar listening + level meter updates
   - verify transcript injects into focused text field

6. Read-aloud:
   - select text in another app and press Option+R
   - verify speaking state and playback
   - repeat with empty selection and verify explicit "No selected text." error

7. Settings persistence:
   - change hotkeys; verify conflict detection blocks duplicates
   - change voice/speed; relaunch app and verify persisted values

8. History/privacy:
   - verify entries include metadata (latency/request id for dictation)
   - clear history and verify empty state

9. Regression checks:
   - run ./scripts/run_tests.sh
CHECKLIST
