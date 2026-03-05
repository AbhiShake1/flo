# 07 Release Readiness Checklist

Use this checklist for Windows parity release candidates.

## Preconditions

1. `apps/windows/docs/04-controller-action-ledger.md` has no rows outside `Parity`.
2. `apps/windows/docs/05-ui-parity-spec.md` has no rows outside `Locked`.
3. `apps/windows/docs/parity-tracker.md` milestones and gates are all `Parity`.
4. Signing readiness is explicitly confirmed for GA MSIX/winget release.

## Execution Commands

1. Preview gate run (allows `In Progress` while validating pipeline):
   - `apps/windows/scripts/release-readiness.sh preview`
2. Strict gate run (required for release candidate):
   - `apps/windows/scripts/release-readiness.sh strict`
3. ZIP package generation:
   - `apps/windows/scripts/package-zip.sh <version>`
4. MSIX/winget prep (GA blocked until signing readiness):
   - `SIGNING_READY=true RELEASE_CHANNEL=ga apps/windows/scripts/prepare-msix-winget.sh <version>`

## 48h Soak Protocol

1. Install from ZIP on Win10 and Win11 clean environments.
2. Run full acceptance matrix twice per day:
   - dictation hold flow
   - read-selected UIA/clipboard fallback
   - elevated target relaunch flow
   - onboarding permission gating
   - provider failover ordering
3. Review crash/error telemetry every 12 hours.
4. Record all issues in `apps/windows/docs/status/week-XX.md`.
5. Release only after 2 consecutive green strict runs with zero parity regressions.

## Signoff

1. Engineering signoff: controller/platform/ui owners.
2. QA signoff: acceptance matrix + compatibility matrix.
3. Release manager signoff: packaging checksums + rollback pointer validation.
