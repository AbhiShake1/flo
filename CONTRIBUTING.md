# Contributing to flo

Thanks for your interest in improving `flo`.

## Development Setup
1. Install Xcode 16+ command line tools.
2. Clone the repository.
3. Copy local config template if needed:
   - `cp .env.local.example .env.local`
4. Build the project:
   - `swift build`
5. Run tests:
   - `./scripts/run_tests.sh`

## Pull Request Rules
- Keep PRs focused and small enough to review.
- Include tests for behavior changes when possible.
- Update docs for any user-facing behavior or release process changes.
- Ensure CI is green before requesting review.

## DCO Sign-off (Required)
This repository requires Developer Certificate of Origin (DCO) sign-off on every commit.

Use one of these approaches:
- `git commit -s -m "your message"`
- `git commit --signoff -m "your message"`

Each commit message must include a line like:
`Signed-off-by: Your Name <you@example.com>`

## Reporting Bugs
Use the bug issue template and include:
- Steps to reproduce
- Expected result
- Actual result
- Logs/screenshots if relevant
- macOS version and CPU architecture
