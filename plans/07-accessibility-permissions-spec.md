# P07 Accessibility and Permissions Spec

## Required Permissions
- Microphone: for dictation capture.
- Accessibility: for synthetic key events and focused-app interactions.
- Input Monitoring: for global hotkeys.

## Permission UX
1. Detect current permission states on startup.
2. Show checklist in onboarding and settings.
3. Provide deep links/instructions to System Settings pages.
4. Re-check status after returning to app.

## Behavior by Missing Permission
- Missing microphone: disable dictation.
- Missing accessibility/input monitoring: disable injection + global shortcut actions.
- Always show actionable remediation message.
