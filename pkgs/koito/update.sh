#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-update curl jq nix prefetch-yarn-deps
# Usage: ./update.sh [--version <X>]
# Defaults to the latest GitHub release.
#
# default.nix wraps everything in a let-binding (so .#koito has no top-level
# src). We drive nix-update against .#koito.backend, which inherits src + has
# vendorHash. That single call updates version, src.hash, and vendorHash in
# the shared let-binding (nix-update edits by file, not by attr path).
#
# We post-process two things it can't:
#   - The yarnOfflineCache hash (fetchYarnDeps is not a nix-update hash type)
#   - The pinned buildGoXYModule, kept in sync with upstream go.mod

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FILE="$HERE/default.nix"
FLAKE_ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"

TOKEN_FILE="$HOME/.config/nix/access-tokens.conf"
if [[ -z "${GITHUB_TOKEN:-}" && -f "$TOKEN_FILE" ]]; then
  GITHUB_TOKEN=$(sed -n 's/.*github\.com=\([^ ]*\).*/\1/p' "$TOKEN_FILE")
  export GITHUB_TOKEN
fi

(cd "$FLAKE_ROOT" && nix-update --flake --use-github-releases koito.backend "$@")

NEW_VERSION=$(grep 'version = ' "$FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Current version after nix-update: $NEW_VERSION"

# Refresh the yarn offline cache hash from upstream's client/yarn.lock.
echo "Prefetching yarn offline cache..."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
curl -sL "https://raw.githubusercontent.com/gabehf/koito/v${NEW_VERSION}/client/yarn.lock" \
  -o "$WORK/yarn.lock"
if [[ ! -s "$WORK/yarn.lock" ]]; then
  echo "ERROR: failed to fetch client/yarn.lock for v${NEW_VERSION}" >&2
  exit 1
fi
YARN_HASH=$(prefetch-yarn-deps "$WORK/yarn.lock")
if [[ "$YARN_HASH" != sha256-* ]]; then
  YARN_HASH=$(nix hash convert --hash-algo sha256 --to sri "$YARN_HASH")
fi
echo "Yarn offline cache hash: $YARN_HASH"

# Rewrite the second `hash = "sha256-..."` occurrence (the first is src.hash,
# already handled by nix-update; the second is the yarnOfflineCache hash).
awk -v new_yarn="$YARN_HASH" '
  /hash = "sha256-/ && !src_seen { src_seen=1; print; next }
  /hash = "sha256-/ && !yarn_done { sub(/"sha256-[^"]*"/, "\"" new_yarn "\""); yarn_done=1 }
  { print }
' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

# Sync the pinned Go builder with upstream go.mod (unpinned buildGoModule
# is left alone so nixpkgs' default Go can roll forward).
OLD_GO_BUILDER=$(grep -oP 'buildGo\d+Module' "$FILE" | head -1 || true)
if [[ -z "$OLD_GO_BUILDER" ]]; then
  echo "default.nix uses unpinned buildGoModule; nothing to sync."
  exit 0
fi

echo "Inspecting upstream go.mod for Go version..."
GO_MOD_LINE=$(curl -sL "https://raw.githubusercontent.com/gabehf/koito/v${NEW_VERSION}/go.mod" \
  | awk '/^go [0-9]+\.[0-9]+/ { print $2; exit }')
if [[ -z "$GO_MOD_LINE" ]]; then
  echo "ERROR: could not read 'go <version>' from upstream go.mod" >&2
  exit 1
fi
GO_MAJOR_MINOR=$(echo "$GO_MOD_LINE" | awk -F. '{ print $1 $2 }')
NEW_GO_BUILDER="buildGo${GO_MAJOR_MINOR}Module"
echo "Upstream requires Go $GO_MOD_LINE -> $NEW_GO_BUILDER"

if [[ "$OLD_GO_BUILDER" == "$NEW_GO_BUILDER" ]]; then
  exit 0
fi
if ! nix eval --impure --expr "(import <nixpkgs> {}).${NEW_GO_BUILDER}.name" >/dev/null 2>&1; then
  echo "ERROR: $NEW_GO_BUILDER is not available in nixpkgs." >&2
  exit 1
fi
echo "Switching Go builder: $OLD_GO_BUILDER -> $NEW_GO_BUILDER"
sed -i "s/\\b${OLD_GO_BUILDER}\\b/${NEW_GO_BUILDER}/g" "$FILE"
