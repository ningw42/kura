#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-update
# Usage: ./update.sh [--version <X>]
# Defaults to the latest GitHub release.

set -euo pipefail

# Reuse the GitHub token from ~/.config/nix/access-tokens.conf so nix-update's
# version-discovery REST call doesn't hit the unauthenticated rate limit.
TOKEN_FILE="$HOME/.config/nix/access-tokens.conf"
if [[ -z "${GITHUB_TOKEN:-}" && -f "$TOKEN_FILE" ]]; then
  GITHUB_TOKEN=$(sed -n 's/.*github\.com=\([^ ]*\).*/\1/p' "$TOKEN_FILE")
  export GITHUB_TOKEN
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
FLAKE_ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
cd "$FLAKE_ROOT"

exec nix-update --flake --use-github-releases router-maestro "$@"
