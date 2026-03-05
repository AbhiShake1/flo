# 05 UI Parity Spec

Scope: strict visual and behavior parity for `apps/windows` against macOS surfaces.

Reference sources:
- `apps/macos/Sources/Infrastructure/FloatingBarWindowManager.swift`
- `apps/macos/Sources/FloApp/FloApp.swift`
- `apps/macos/Sources/Features/FloController.swift`

Status legend: `Locked`, `Needs Capture`, `Exception`.

## 1. Surface Inventory (all must be parity)

| Surface | macOS reference | Windows target | Status |
|---|---|---|---|
| Main settings shell (all tabs) | `FloApp.swift` | Native Win32 window with identical IA + copy | Needs Capture |
| Onboarding/login stage flow | `FloApp.swift` + `FloController` | Native Win32 stage flow and gating | Needs Capture |
| Permissions stage | `FloApp.swift` permissions section | Native Win32 permissions pane + OS deeplinks | Needs Capture |
| History + provider workbench | `FloApp.swift` | Native Win32 pages and CRUD semantics | Needs Capture |
| Tray/menu shell | macOS status item menus | Windows tray icon + context menu parity | Needs Capture |
| Recorder chip (bottom-center) | `FloatingBarWindowManager.swift` | Always-on-top bottom-center Win32 surface | Locked |
| In-chip banners (error/success) | `FloatingBarWindowManager.swift` | Same tone, auto-dismiss, dismiss affordance | Locked |

## 2. Recorder Chip Tokens (Locked)

### 2.1 Geometry

| Token | Value | Source |
|---|---:|---|
| `chip.left.width` | 37 px | `Metrics.leftSectionWidth` |
| `chip.left.height` | 9 px | `Metrics.leftSectionHeight` |
| `chip.right.width.idle` | 20 px | `Metrics.rightSectionWidth` |
| `chip.right.height.idle` | 9 px | `Metrics.rightSectionHeight` |
| `chip.right.width.speaking` | 60 px | `Metrics.speakingRightSectionWidth` |
| `chip.right.height.speaking` | 18 px | `Metrics.speakingRightSectionHeight` |
| `chip.section.gap` | 2 px | `Metrics.sectionGap` |
| `chip.bottom.inset` | 14 px from visible frame bottom | `Metrics.panelBottomInset` |
| `chip.centering` | horizontal center of primary display visible frame | `positionPanel(...)` |

### 2.2 Banner layout

| Token | Value | Source |
|---|---:|---|
| `banner.min.width` | 300 px | `Metrics.errorMinWidth` |
| `banner.max.width` | 560 px | `Metrics.errorMaxWidth` |
| `banner.min.height` | 48 px | `Metrics.errorMinHeight` |
| `banner.corner.radius` | 12 px | `Metrics.errorCornerRadius` |
| `banner.pad.horizontal` | 12 px | `Metrics.errorHorizontalPadding` |
| `banner.pad.vertical` | 10 px | `Metrics.errorVerticalPadding` |
| `banner.dismiss.size` | 20 px | `Metrics.errorDismissSize` |
| `banner.dismiss.trailing` | 10 px | `Metrics.errorDismissTrailingPadding` |
| `banner.text.spacing` | 10 px | `Metrics.errorTextSpacing` |

### 2.3 Color and alpha rules

| Element | Token/Rule |
|---|---|
| Left idle section fill | `black @ 56%` |
| Left idle section border | `white @ 56%`, 1 px |
| Right section bg alpha (idle/error, no selected text) | `white @ 6%` |
| Right section bg alpha (idle/error, selected text) | `white @ 12%` |
| Right section bg alpha (listening/transcribing/injecting) | `white @ 6%` |
| Right section bg alpha (speaking) | `white @ 20%` |
| Success banner tone | green fill `@30%`, border `@86%`, 1.2 px |
| Error banner tone | red fill `@33%`, border `@88%`, 1.2 px |

## 3. Recorder Chip State Model (Locked)

State machine source: `apply(state:)`, `isBusy`, `canTriggerRead`, `readAlpha`, and waveform mode rules.

| State | Primary waveform mode | Dictation button enabled | Read button enabled | Notes |
|---|---|---|---|---|
| `Idle` | `idle` | Yes | Yes | Read alpha depends on selected text (1.0/0.68). |
| `Listening` | `listening` (real level meter) | Yes | No | Busy false, but read disabled. |
| `Transcribing` | `processing` | No | No | Busy true. |
| `Injecting` | `processing` | No | No | Busy true. |
| `Speaking` | `processing` | No | Yes (acts as stop) | Right segment expands to speaking geometry. |
| `Error(message)` | `idle` + error banner | No while banner visible | No while banner visible | Error auto-dismiss and manual dismiss supported. |

## 4. Motion and Timing (Locked)

| Motion | Behavior |
|---|---|
| Chip reposition/resize | Animate with platform window animation when reduce-motion is off, otherwise jump-cut. |
| Success banner auto-dismiss | 2.2 seconds (`Metrics.successAutoDismissDelay`). |
| Error banner auto-dismiss | 2.8 seconds (`Metrics.errorAutoDismissDelay`). |
| Selection availability polling | 350 ms periodic refresh for read-button availability. |
| Audio level update cadence | driven by capture callback; macOS baseline service emits every ~50 ms. |

## 5. Tooltip and Hint Copy (Locked)

| Context | Message |
|---|---|
| Dictation hint default | `Hold your dictation shortcut to start dictating, or click to start or stop dictation.` |
| Read hint default | `Read selected text aloud.` |
| Read hint while speaking | `Click to stop narration.` |
| Read hint when no selection | `Click to try narrating selected text.` |

## 6. DPI and Rendering Requirements (Locked)

1. Pass side-by-side review at 100%, 125%, and 150% DPI.
2. Chip geometry tokens scale without clipping of waveform bars, stop icon, or banner dismiss affordance.
3. Banner text wraps using the same width constraints and min-height behavior.
4. Keyboard focus ring and accessibility names remain visible and non-overlapping at all DPIs.

## 7. Remaining Capture Work (before parity signoff)

1. Settings window typography stack, spacing grid, and control heights from macOS reference screenshots.
2. Tray/menu spacing, icon sizes, and separators.
3. Onboarding stage transition timings and empty/error illustrations.
4. History/provider table row heights and inline notice variants.

Freeze rule: once rows above are captured and marked `Locked`, no visual token or motion change is allowed unless parity review reopens the row in `apps/windows/docs/parity-tracker.md`.
