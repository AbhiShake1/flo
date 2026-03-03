# Security Policy

## Reporting A Vulnerability
Per repository policy, security issues are reported via public GitHub Issues.

When filing a report:
- Use title prefix: `[security]`.
- Include affected version/tag and reproduction details.
- Avoid posting active exploit code until a mitigation exists.

## Severity Labels
Maintainers will apply one of:
- `severity:critical`
- `severity:high`
- `severity:medium`
- `severity:low`

## Response Targets
- Initial triage: within 2 business days.
- Remediation plan: within 7 business days for critical/high issues.
- Patch release target: as soon as a fix is validated and notarized.

## Scope
Security reports include:
- Credential/token handling
- Keychain usage
- Host allowlist bypass risks
- Arbitrary code execution vectors
- Update/distribution integrity risks
