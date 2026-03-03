# P00 Plan Orchestration

## Objective
Create a decision-complete planning package for `flo` before any source scaffolding. This document defines sequencing, ownership, and dependency constraints.

## Guardrails
- Do not scaffold source code until `P00` through `P10` are complete.
- All plan docs must be internally consistent on auth gating, hotkeys, and platform assumptions.
- Shipping target: direct download + notarized app, macOS 15+.

## Milestones
1. M0: Planning skeleton created (`flo/plans` + all plan files present).
2. M1: Requirements/spec wave complete (`P01` to `P10`).
3. M2: Scaffolding plan complete (`P11`).
4. M3: Execution workbreakdown complete (`P12`).
5. M4: Release/risk plans complete (`P13`, `P14`).
6. M5: Source scaffolding starts.

## Dependency Backbone
```text
T0 P00
├─ Wave A: P01 P02 P03 P04 P05 P06 P07 P08 P09 P10
├─ T1: P11 (depends on P01..P10)
├─ T2: P12 (depends on P11)
└─ Wave B: P13 P14
```

## Roles (Logical)
- Product/UX: P01, P02.
- Platform/Auth: P03, P06, P07.
- Media Pipelines: P04, P05, P08.
- Security/Compliance: P09, P13, P14.
- QA: P10.
- Architecture Integrator: P11, P12.

## Exit Criteria
- All plan files approved.
- Public interfaces frozen.
- Build/verification strategy defined.
