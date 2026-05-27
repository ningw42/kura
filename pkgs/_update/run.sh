#!/usr/bin/env bash
# Shared driver invoked from each package's passthru.updateScript.
# This is the only script in the repo that knows nix-update's CLI.
#
# Runtime dependencies (nix-update, jq, curl, prefetch-npm-deps, git,
# nodejs_22, nix) are provided by the flake's shell.nix, which the
# nixpkgs maintainers/scripts/update.py runner wraps every invocation in.
#
# Usage (from default.nix):
#   passthru.updateScript = [
#     ../_update/run.sh
#     "--attr" "<attrpath>"           [repeatable]
#     "--pre-hook" "<hook-spec>"      [repeatable]
#     "--post-hook" "<hook-spec>"     [repeatable]
#     <any nix-update flag>           [passed through verbatim]
#   ];
#
# Hook spec format: `name:arg1:arg2[:arg3...]`. Dispatched to functions in hooks.sh.
# Known hooks: sync-go-builder, regen-npm-lockfile (see hooks.sh).

set -euo pipefail

# We get copied into the nix store, so BASH_SOURCE points there for sourcing
# our siblings. The runner cd's into either the original repo root (no-commit)
# or a worktree of it (commit mode); both have shell.nix from the kura root.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_ROOT="$PWD"

# shellcheck source=token.sh
source "$HERE/token.sh"
# shellcheck source=hooks.sh
source "$HERE/hooks.sh"

ATTRS=()
PRE_HOOKS=()
POST_HOOKS=()
PASSTHROUGH=()
EXPLICIT_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --attr)       ATTRS+=("$2"); shift 2 ;;
    --pre-hook)   PRE_HOOKS+=("$2"); shift 2 ;;
    --post-hook)  POST_HOOKS+=("$2"); shift 2 ;;
    --version)    EXPLICIT_VERSION="$2"; PASSTHROUGH+=("$1" "$2"); shift 2 ;;
    *)            PASSTHROUGH+=("$1"); shift ;;
  esac
done

# Fallback: if no --attr was given, use the nixpkgs runner's UPDATE_NIX_ATTR_PATH.
if [[ ${#ATTRS[@]} -eq 0 ]]; then
  if [[ -n "${UPDATE_NIX_ATTR_PATH:-}" ]]; then
    ATTRS+=("$UPDATE_NIX_ATTR_PATH")
  else
    echo "[run.sh] ERROR: no --attr given and UPDATE_NIX_ATTR_PATH unset" >&2
    exit 1
  fi
fi

# Resolve PKG_DIR from the first attr's top-level segment (koito.backend -> pkgs/koito).
TOP_ATTR="${ATTRS[0]%%.*}"
export KURA_PKG_DIR="$FLAKE_ROOT/pkgs/$TOP_ATTR"
if [[ ! -d "$KURA_PKG_DIR" ]]; then
  echo "[run.sh] ERROR: $KURA_PKG_DIR not found (derived from attr ${ATTRS[0]})" >&2
  exit 1
fi

# Discover NEW_VERSION before pre-hooks if any are configured (they need it for
# tag-cloning). Order: explicit --version > GitHub API for the first hook's
# owner/repo > defer to nix-update.
_discover_version() {
  if [[ -n "$EXPLICIT_VERSION" ]]; then
    KURA_VERSION="$EXPLICIT_VERSION"
    return
  fi
  if [[ ${#PRE_HOOKS[@]} -eq 0 ]]; then
    return  # post-hooks read KURA_VERSION after nix-update runs
  fi
  # Parse owner/repo from the first pre-hook spec: `name:owner/repo:...`
  local first="${PRE_HOOKS[0]}"
  local owner_repo
  owner_repo=$(echo "$first" | cut -d: -f2)
  local curl_args=(-s)
  [[ -n "${GITHUB_TOKEN:-}" ]] && curl_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
  KURA_VERSION=$(curl "${curl_args[@]}" \
    "https://api.github.com/repos/${owner_repo}/releases/latest" \
    | jq -r .tag_name | sed 's/^v//')
  if [[ -z "$KURA_VERSION" || "$KURA_VERSION" == "null" ]]; then
    echo "[run.sh] ERROR: could not determine latest version for $owner_repo" >&2
    exit 1
  fi
  export KURA_VERSION
  echo "[run.sh] Discovered target version: $KURA_VERSION"
}

_run_hook() {
  local spec="$1"
  IFS=':' read -r name arg1 arg2 arg3 <<<"$spec"
  case "$name" in
    sync-go-builder)     sync_go_builder    "$arg1" "$arg2" ;;
    regen-npm-lockfile)  regen_npm_lockfile "$arg1" "$arg2" "${arg3:-}" ;;
    *) echo "[run.sh] ERROR: unknown hook '$name'" >&2; exit 1 ;;
  esac
}

# Pre-hooks: run before any nix-update call.
if [[ ${#PRE_HOOKS[@]} -gt 0 ]]; then
  _discover_version
  # Short-circuit: if we already match the target, skip pre-hooks AND nix-update
  # (pre-hooks like regen-npm-lockfile clone the upstream tag, which is wasteful
  # when nothing changed).
  OLD_VERSION=$(grep 'version = ' "$KURA_PKG_DIR/default.nix" | head -1 | sed 's/.*"\(.*\)".*/\1/')
  if [[ "$OLD_VERSION" == "${KURA_VERSION:-}" ]]; then
    echo "[run.sh] Already at $KURA_VERSION; skipping pre-hooks and nix-update."
    exit 0
  fi
  for spec in "${PRE_HOOKS[@]}"; do _run_hook "$spec"; done
fi

# Drive nix-update once per --attr. First call may discover the version;
# subsequent calls pin to whatever ended up in default.nix.
PINNED_VERSION="$EXPLICIT_VERSION"
for i in "${!ATTRS[@]}"; do
  attr="${ATTRS[$i]}"
  args=(--flake "${PASSTHROUGH[@]}")
  if [[ -n "$PINNED_VERSION" && $i -gt 0 ]]; then
    # Only inject if PASSTHROUGH didn't already supply --version
    if ! printf '%s\n' "${PASSTHROUGH[@]}" | grep -qx -- '--version'; then
      args+=(--version "$PINNED_VERSION")
    fi
  fi
  echo "[run.sh] nix-update ${args[*]} $attr"
  ( cd "$FLAKE_ROOT" && nix-update "${args[@]}" "$attr" )

  # After the first call, read the resolved version from default.nix to pin
  # later --attr calls and to feed post-hooks.
  if [[ -z "$PINNED_VERSION" ]]; then
    PINNED_VERSION=$(grep 'version = ' "$KURA_PKG_DIR/default.nix" | head -1 | sed 's/.*"\(.*\)".*/\1/')
  fi
done

export KURA_VERSION="$PINNED_VERSION"
echo "[run.sh] Resolved version: $KURA_VERSION"

# Post-hooks: run after all nix-update calls succeed.
for spec in "${POST_HOOKS[@]}"; do _run_hook "$spec"; done
