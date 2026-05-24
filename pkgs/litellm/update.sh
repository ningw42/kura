#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-update
# Usage: ./update.sh [--version <X>]
# Defaults to the latest stable GitHub release.
#
# Starting from 1.84.0 litellm follows semver; the old `-stable` tag variants
# we used to special-case no longer exist. --version-regex filters out any
# residual prereleases (rc, alpha, ...) and rejects any lingering -stable tags.

set -euo pipefail

TOKEN_FILE="$HOME/.config/nix/access-tokens.conf"
if [[ -z "${GITHUB_TOKEN:-}" && -f "$TOKEN_FILE" ]]; then
  GITHUB_TOKEN=$(sed -n 's/.*github\.com=\([^ ]*\).*/\1/p' "$TOKEN_FILE")
  export GITHUB_TOKEN
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
FLAKE_ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"

(cd "$FLAKE_ROOT" && nix-update \
  --flake \
  --use-github-releases \
  --version-regex '^v?([0-9]+\.[0-9]+\.[0-9]+)$' \
  litellm "$@")
