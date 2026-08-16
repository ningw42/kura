#!/usr/bin/env bash
# Evaluate matrix.nix against an optional baseline commit. Stdout is the JSON
# matrix; progress messages go to stderr so callers can capture it directly.
set -euo pipefail

baseline_sha="${1:-}"
previous_worktree=""

cleanup() {
  if [[ -n "$previous_worktree" ]]; then
    git worktree remove --force "$previous_worktree" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# A branch's first push has an all-zero `github.event.before`. With no usable
# baseline, matrix.nix intentionally returns the full configured matrix.
if [[ "$baseline_sha" =~ ^0+$ ]]; then
  baseline_sha=""
fi

if [[ -n "$baseline_sha" ]]; then
  if ! git cat-file -e "$baseline_sha^{commit}" 2>/dev/null; then
    if ! git fetch --no-tags --depth=1 origin "$baseline_sha"; then
      echo "Could not fetch baseline $baseline_sha; evaluating the full matrix" >&2
      baseline_sha=""
    fi
  fi
fi

if [[ -n "$baseline_sha" ]]; then
  previous_worktree=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/kura-previous.XXXXXX")
  rmdir "$previous_worktree"
  git worktree add --detach "$previous_worktree" "$baseline_sha" >&2
  echo "Baseline: $baseline_sha" >&2
else
  echo "No usable baseline; evaluating the full matrix" >&2
fi

KURA_PREVIOUS_FLAKE="$previous_worktree" nix eval --json --impure --expr '
  let
    previousPath = builtins.getEnv "KURA_PREVIOUS_FLAKE";
  in
  import ./matrix.nix {
    self = builtins.getFlake (toString ./.);
    previous =
      if previousPath == "" then
        null
      else
        builtins.getFlake previousPath;
  }
'
