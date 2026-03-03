# P13 Release and Notarization Plan

## Distribution
- Direct download DMG/ZIP.
- Signed with Developer ID Application cert.
- Notarized with Apple notary service and stapled.

## CI/CD Steps
1. Build release artifact.
2. Codesign app bundle.
3. Submit for notarization.
4. Poll status, staple ticket.
5. Publish checksums + release notes.

## Runtime Hardening
- Enable hardened runtime.
- Entitlements minimized to required set.

## Update Channel
- v1: manual update checks.
- v1.1: appcast-based update feed.
