#!/usr/bin/env bash
set -euo pipefail

# Configure repository governance settings expected by flo launch policy.
# Usage:
#   ./scripts/configure_github_repo_settings.sh [owner/repo]
#
# Defaults:
#   repo: current gh repo
#   branch: main

REPO="${1:-}"
BRANCH="${FLO_DEFAULT_BRANCH:-main}"

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

if [[ -z "$REPO" ]]; then
  echo "Unable to resolve repository. Pass owner/repo explicitly."
  exit 1
fi

echo "Configuring repository settings for $REPO"

echo "[1/3] Enable auto-delete merged branches and squash merge"
gh api \
  --method PATCH \
  "repos/$REPO" \
  -f delete_branch_on_merge=true \
  -f allow_squash_merge=true \
  -f allow_merge_commit=false \
  -f allow_rebase_merge=false \
  -f allow_auto_merge=true > /dev/null

echo "[2/3] Apply branch protection to $BRANCH"

cat <<JSON | gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/$REPO/branches/$BRANCH/protection" \
  --input - > /dev/null
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "CI / dco-check",
      "CI / build-test",
      "CI / script-lint",
      "dependency-review / dependency-review",
      "security / security"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": true
}
JSON

echo "[3/3] Repository governance configuration applied"
