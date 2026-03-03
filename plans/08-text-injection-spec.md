# P08 Text Injection Spec

## Objective
Insert transcript into currently focused input reliably.

## Smart Paste Strategy
1. Save current clipboard contents.
2. Put transcript in clipboard.
3. Send Cmd+V to focused app.
4. Restore previous clipboard after short delay.

## Fallbacks
- If paste fails, optionally type keystrokes as backup (v1.1 toggle).
- In v1, failure returns clear error toast + history record.

## Constraints
- Preserve clipboard fidelity where possible.
- Avoid injection in secure fields if detectable.
