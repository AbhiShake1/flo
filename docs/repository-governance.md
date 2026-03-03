# Repository Governance Setup

## Required GitHub Settings
- Require pull requests for `main`
- Require at least 1 approving review
- Require status checks:
  - `CI / dco-check`
  - `CI / build-test`
  - `CI / script-lint`
  - `dependency-review / dependency-review`
  - `security / security`
- Require linear history
- Block force pushes and branch deletions
- Enable auto-delete merged branches
- Enable squash merge

## Automated Setup Script
Use:

```bash
./scripts/configure_github_repo_settings.sh AbhiShake1/flo
```

This script applies repository-level merge settings and branch protection via GitHub API.
It requires maintainer/admin permissions.
