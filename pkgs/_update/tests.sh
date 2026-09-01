#!/usr/bin/env bash

set -euo pipefail

SOURCE_ROOT="${KURA_SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TESTS_FAILED=0

run_test() {
  local name="$1"
  shift

  if ( "$@" ); then
    echo "ok - $name"
  else
    echo "not ok - $name" >&2
    TESTS_FAILED=1
  fi
}

sync_go_builder_runs_before_nix_update() {
  local work
  work=$(mktemp -d)
  trap 'rm -rf "$work"' RETURN

  mkdir -p "$work/root/pkgs/copilotd" "$work/bin"
  cat >"$work/root/pkgs/copilotd/default.nix" <<'EOF'
{ buildGo126Module }:
buildGo126Module {
  pname = "copilotd";
  version = "0.5.0";
}
EOF

  printf '#!%s\n' "$BASH" >"$work/bin/curl"
  cat >>"$work/bin/curl" <<'EOF'
printf 'module example.com/copilotd\n\ngo 1.27\n'
EOF

  printf '#!%s\n' "$BASH" >"$work/bin/nix"
  cat >>"$work/bin/nix" <<'EOF'
if [[ "$*" == *'builtins.hasAttr "buildGo127Module"'* ]]; then
  printf 'true\n'
  exit 0
fi
printf 'unexpected nix invocation: %s\n' "$*" >&2
exit 1
EOF

  printf '#!%s\n' "$BASH" >"$work/bin/nix-update"
  cat >>"$work/bin/nix-update" <<'EOF'
if grep -q 'buildGo126Module' pkgs/copilotd/default.nix; then
  echo 'nix-update ran before the Go builder was synchronized' >&2
  exit 1
fi
grep -q 'buildGo127Module' pkgs/copilotd/default.nix
EOF

  chmod +x "$work/bin/"*

  (
    cd "$work/root"
    PATH="$work/bin:$PATH" bash "$SOURCE_ROOT/pkgs/_update/run.sh" \
      --attr copilotd \
      --version 0.6.0 \
      --pre-hook sync-go-builder:ningw42/copilotd:v
  )

  ! grep -q 'buildGo126Module' "$work/root/pkgs/copilotd/default.nix"
  grep -q 'buildGo127Module' "$work/root/pkgs/copilotd/default.nix"
}

all_sync_go_builder_hooks_are_pre_hooks() {
  local match file line previous_hook

  while IFS= read -r match; do
    file=${match%%:*}
    match=${match#*:}
    line=${match%%:*}
    previous_hook=$(
      head -n "$((line - 1))" "$file" \
        | grep -E '"--(pre|post)-hook"' \
        | tail -n 1
    )
    if [[ "$previous_hook" != *'"--pre-hook"'* ]]; then
      echo "$file:$line registers sync-go-builder after nix-update" >&2
      return 1
    fi
  done < <(grep -nH '"sync-go-builder:' "$SOURCE_ROOT"/pkgs/*/default.nix)
}

auto_update_workflow_fails_on_package_errors() {
  grep -Fq 'nix run .#update -- --skip-prompt --no-keep-going' \
    "$SOURCE_ROOT/.github/workflows/auto-update-packages.yml"
}

run_test 'sync-go-builder runs before nix-update' sync_go_builder_runs_before_nix_update
run_test 'all sync-go-builder hooks are pre-hooks' all_sync_go_builder_hooks_are_pre_hooks
run_test 'auto-update workflow fails on package errors' auto_update_workflow_fails_on_package_errors

exit "$TESTS_FAILED"
