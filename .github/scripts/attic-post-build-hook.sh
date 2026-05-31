#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: attic-post-build-hook.sh <install|hook|push> [cache=kura]

install  Install a composed Nix post-build hook for later workflow steps.
hook     Internal entry point invoked by Nix post-build-hook.
push     Push the locally built paths collected by the hook to Attic.
EOF
}

runner_temp() {
  printf '%s\n' "${RUNNER_TEMP:-/tmp}"
}

script_path() {
  case "$0" in
    /*) printf '%s\n' "$0" ;;
    *)
      local dir
      dir=$(cd "$(dirname "$0")" && pwd -P)
      printf '%s/%s\n' "$dir" "$(basename "$0")"
      ;;
  esac
}

shell_quote() {
  printf '%q' "$1"
}

post_build_hook_from_file() {
  awk '
    /^[[:space:]]*post-build-hook[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      sub(/^"/, "")
      sub(/"$/, "")
      print
    }
  ' "$1" | tail -n 1
}

post_build_hook_from_text() {
  awk '
    /^[[:space:]]*post-build-hook[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      sub(/^"/, "")
      sub(/"$/, "")
      print
    }
  ' | tail -n 1
}

current_post_build_hook() {
  if [[ -n "${CACHIX_DAEMON_DIR:-}" && -f "$CACHIX_DAEMON_DIR/post-build-hook.sh" ]]; then
    printf 'CACHIX_DAEMON_DIR\t%s\n' "$CACHIX_DAEMON_DIR/post-build-hook.sh"
    return 0
  fi

  local hook
  if [[ -n "${NIX_CONF:-}" ]]; then
    hook=$(printf '%s\n' "$NIX_CONF" | post_build_hook_from_text)
    if [[ -n "$hook" ]]; then
      printf 'NIX_CONF\t%s\n' "$hook"
      return 0
    fi
  fi

  if [[ -n "${NIX_USER_CONF_FILES:-}" ]]; then
    local old_ifs conf
    old_ifs=$IFS
    IFS=:
    for conf in $NIX_USER_CONF_FILES; do
      IFS=$old_ifs
      if [[ -f "$conf" ]]; then
        hook=$(post_build_hook_from_file "$conf")
        if [[ -n "$hook" ]]; then
          printf 'NIX_USER_CONF_FILES\t%s\n' "$hook"
          return 0
        fi
      fi
      IFS=:
    done
    IFS=$old_ifs
  fi
}

install_hook() {
  if [[ -z "${GITHUB_ENV:-}" ]]; then
    echo "GITHUB_ENV is not set; this command is intended for GitHub Actions" >&2
    exit 1
  fi

  local state_dir paths_dir events_log wrapper config hook_line hook_source original_hook this_script
  state_dir="$(runner_temp)/attic-post-build-hook"
  paths_dir="$state_dir/paths"
  events_log="$state_dir/events.log"
  wrapper="$state_dir/post-build-hook.sh"
  config="$state_dir/nix.conf"
  hook_line=$(current_post_build_hook || true)
  if [[ -n "$hook_line" ]]; then
    hook_source=${hook_line%%$'\t'*}
    original_hook=${hook_line#*$'\t'}
  else
    hook_source=none
    original_hook=
  fi
  this_script=$(script_path)

  mkdir -p "$paths_dir"
  : > "$events_log"

  local quoted_paths_dir quoted_events_log quoted_wrapper quoted_original_hook quoted_this_script
  quoted_paths_dir=$(shell_quote "$paths_dir")
  quoted_events_log=$(shell_quote "$events_log")
  quoted_wrapper=$(shell_quote "$wrapper")
  quoted_original_hook=$(shell_quote "$original_hook")
  quoted_this_script=$(shell_quote "$this_script")

  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
export ATTIC_POST_BUILD_PATHS_DIR=$quoted_paths_dir
export ATTIC_POST_BUILD_EVENTS_LOG=$quoted_events_log
export ATTIC_POST_BUILD_HOOK=$quoted_wrapper
export ATTIC_ORIGINAL_POST_BUILD_HOOK=$quoted_original_hook
exec bash $quoted_this_script hook "\$@"
EOF
  chmod +x "$wrapper"

  printf 'post-build-hook = %s\n' "$wrapper" > "$config"

  {
    echo "ATTIC_POST_BUILD_PATHS_DIR=$paths_dir"
    echo "ATTIC_POST_BUILD_EVENTS_LOG=$events_log"
    echo "ATTIC_POST_BUILD_HOOK=$wrapper"
    echo "ATTIC_ORIGINAL_POST_BUILD_HOOK=$original_hook"
    if [[ -n "${NIX_CONF:-}" ]]; then
      echo "NIX_CONF<<__KURA_ATTIC_NIX_CONF__"
      printf '%s\n' "$NIX_CONF"
      printf 'post-build-hook = %s\n' "$wrapper"
      echo "__KURA_ATTIC_NIX_CONF__"
    else
      echo "NIX_USER_CONF_FILES=$config${NIX_USER_CONF_FILES:+:$NIX_USER_CONF_FILES}"
    fi
  } >> "$GITHUB_ENV"

  echo "::notice::Installed Attic post-build hook collector at $wrapper"
  echo "::notice::Installed via post-build-hook discovery branch: $hook_source"
  if [[ -n "$original_hook" ]]; then
    echo "::notice::Composing with existing post-build hook: $original_hook"
  else
    echo "::warning::No existing post-build hook found; Cachix daemon mode may not be active"
  fi
}

record_out_paths() {
  local paths_dir events_log tmp path kept
  paths_dir="${ATTIC_POST_BUILD_PATHS_DIR:-}"
  events_log="${ATTIC_POST_BUILD_EVENTS_LOG:-}"

  if [[ -z "$paths_dir" || -z "${OUT_PATHS:-}" ]]; then
    return 0
  fi

  mkdir -p "$paths_dir"
  tmp=$(mktemp "$paths_dir/paths.XXXXXX")

  kept=0
  {
    if [[ -n "$events_log" ]]; then
      {
        printf 'hook %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'raw OUT_PATHS: %s\n' "$OUT_PATHS"
        printf 'filtered paths:\n'
      } >> "$events_log"
    fi

    for path in $OUT_PATHS; do
      case "$path" in
        *.drv | *.drv.chroot | *.check | *.lock) ;;
        *)
          printf '%s\n' "$path"
          if [[ -n "$events_log" ]]; then
            printf '  %s\n' "$path" >> "$events_log"
          fi
          kept=$((kept + 1))
          ;;
      esac
    done

    if [[ -n "$events_log" ]]; then
      printf 'kept: %s\n\n' "$kept" >> "$events_log"
    fi
  } > "$tmp"

  if [[ "$kept" -eq 0 ]]; then
    rm -f "$tmp"
  fi
}

run_hook() {
  if ! record_out_paths; then
    echo "attic-post-build-hook: failed to record OUT_PATHS; continuing" >&2
  fi

  if [[ -n "${ATTIC_ORIGINAL_POST_BUILD_HOOK:-}" ]]; then
    if [[ "${ATTIC_ORIGINAL_POST_BUILD_HOOK:-}" == "${ATTIC_POST_BUILD_HOOK:-}" ]]; then
      echo "attic-post-build-hook: original hook points to this wrapper; skipping to avoid recursion" >&2
      return 0
    fi

    if [[ -x "$ATTIC_ORIGINAL_POST_BUILD_HOOK" ]]; then
      if [[ -n "${ATTIC_POST_BUILD_EVENTS_LOG:-}" ]]; then
        printf 'chaining original hook: %s\n\n' "$ATTIC_ORIGINAL_POST_BUILD_HOOK" >> "$ATTIC_POST_BUILD_EVENTS_LOG"
      fi
      "$ATTIC_ORIGINAL_POST_BUILD_HOOK" "$@"
    else
      echo "attic-post-build-hook: original hook is not executable: $ATTIC_ORIGINAL_POST_BUILD_HOOK" >&2
    fi
  fi
}

push_paths() {
  local cache paths_dir events_log to_push count file
  cache="${1:-kura}"
  paths_dir="${ATTIC_POST_BUILD_PATHS_DIR:-$(runner_temp)/attic-post-build-hook/paths}"
  events_log="${ATTIC_POST_BUILD_EVENTS_LOG:-$(runner_temp)/attic-post-build-hook/events.log}"
  to_push="$(runner_temp)/attic-built-paths.txt"

  : > "$to_push"
  if [[ -d "$paths_dir" ]]; then
    for file in "$paths_dir"/paths.*; do
      [[ -e "$file" ]] || continue
      awk 'NF' "$file"
    done | sort -u > "$to_push"
  fi

  count=$(wc -l < "$to_push")
  echo "::notice::Nix post-build hook collected $count locally built path(s) for Attic"

  echo "::group::Attic post-build hook capture log"
  if [[ -s "$events_log" ]]; then
    cat "$events_log"
  else
    echo "::warning::No hook invocations were captured. The collector may not be installed in Nix's active config."
  fi
  echo "::endgroup::"

  echo "::group::Paths to push to Attic"
  cat "$to_push"
  echo "::endgroup::"

  if [[ "$count" -eq 0 ]]; then
    echo "Nothing to push."
    exit 0
  fi

  attic push --stdin "$cache" < "$to_push"
}

case "${1:-}" in
  install)
    install_hook
    ;;
  hook)
    shift
    run_hook "$@"
    ;;
  push)
    shift
    push_paths "${1:-kura}"
    ;;
  *)
    usage
    exit 2
    ;;
esac
