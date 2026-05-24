#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-update curl nix
# Usage: ./update.sh [--version <X>]
# Defaults to the latest GitHub release.
#
# nix-update handles version + src.hash + vendorHash.
# We post-process to keep the pinned buildGoXYModule in sync with upstream go.mod.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FILE="$HERE/default.nix"
FLAKE_ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"

# Reuse the GitHub token from ~/.config/nix/access-tokens.conf so nix-update's
# version-discovery REST call doesn't hit the unauthenticated rate limit.
# nix-prefetch-github (used internally for the source hash) already reads that
# file natively; this just plumbs the same token to nix-update's own API call.
TOKEN_FILE="$HOME/.config/nix/access-tokens.conf"
if [[ -z "${GITHUB_TOKEN:-}" && -f "$TOKEN_FILE" ]]; then
  GITHUB_TOKEN=$(sed -n 's/.*github\.com=\([^ ]*\).*/\1/p' "$TOKEN_FILE")
  export GITHUB_TOKEN
fi

(cd "$FLAKE_ROOT" && nix-update --flake --use-github-releases telepush "$@")

NEW_VERSION=$(grep 'version = ' "$FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')
OLD_GO_BUILDER=$(grep -oP 'buildGo\d+Module' "$FILE" | head -1 || true)

# Unpinned `buildGoModule` is intentional: let nixpkgs' default Go roll forward.
if [[ -z "$OLD_GO_BUILDER" ]]; then
  echo "default.nix uses unpinned buildGoModule; nothing to sync."
  exit 0
fi

echo "Inspecting upstream go.mod for Go version..."
GO_MOD_LINE=$(curl -sL "https://raw.githubusercontent.com/muety/telepush/${NEW_VERSION}/go.mod" \
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
  echo "Either wait for nixpkgs to ship it, or pick a newer builder manually." >&2
  exit 1
fi

echo "Switching Go builder: $OLD_GO_BUILDER -> $NEW_GO_BUILDER"
sed -i "s/\\b${OLD_GO_BUILDER}\\b/${NEW_GO_BUILDER}/g" "$FILE"
