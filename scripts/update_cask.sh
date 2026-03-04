#!/usr/bin/env bash
set -euo pipefail

# Update Casks/flo.rb with a new release version and DMG SHA256.
#
# Usage:
#   ./scripts/update_cask.sh <version> <dmg-sha256> [cask-path]
# Examples:
#   ./scripts/update_cask.sh 0.2.0 7f...ab
#   ./scripts/update_cask.sh v0.2.0 7f...ab Casks/flo.rb

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <version> <dmg-sha256> [cask-path]"
  exit 1
fi

VERSION="${1#v}"
SHA256_RAW="$2"
SHA256="$(printf '%s' "$SHA256_RAW" | tr 'A-F' 'a-f')"
CASK_PATH="${3:-Casks/flo.rb}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid version: $VERSION"
  echo "Expected semver format like 0.2.0"
  exit 1
fi

if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Invalid SHA256: $SHA256_RAW"
  echo "Expected 64 lowercase hex characters"
  exit 1
fi

if [[ ! -f "$CASK_PATH" ]]; then
  echo "Cask file not found: $CASK_PATH"
  exit 1
fi

ruby - "$CASK_PATH" "$VERSION" "$SHA256" <<'RUBY'
path, version, sha256 = ARGV
content = File.read(path)

version_updated = content.sub!(/^(\s*version\s+")[^"]+(")/, "\\1#{version}\\2")
sha_updated = content.sub!(/^(\s*sha256\s+")[^"]+(")/, "\\1#{sha256}\\2")

abort("Unable to update version line in #{path}") unless version_updated
abort("Unable to update sha256 line in #{path}") unless sha_updated

File.write(path, content)
RUBY

grep -q "version \"$VERSION\"" "$CASK_PATH"
grep -q "sha256 \"$SHA256\"" "$CASK_PATH"

echo "Updated $CASK_PATH"
echo "  version: $VERSION"
echo "  sha256:  $SHA256"
