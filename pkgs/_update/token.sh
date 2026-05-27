# Sourceable. Exports GITHUB_TOKEN from ~/.config/nix/access-tokens.conf if
# unset, so nix-update's release-discovery REST call (and our own GitHub API
# probes in hooks) hit the 5000/hr authenticated rate limit instead of 60/hr.
#
# nix-prefetch-github (used internally by nix-update for source hashes) reads
# the access-tokens file natively; this bridge is only needed for nix-update
# itself and for plain curl calls in hooks.

_kura_load_github_token() {
  local token_file="$HOME/.config/nix/access-tokens.conf"
  if [[ -z "${GITHUB_TOKEN:-}" && -f "$token_file" ]]; then
    GITHUB_TOKEN=$(sed -n 's/.*github\.com=\([^ ]*\).*/\1/p' "$token_file")
    export GITHUB_TOKEN
  fi
}

_kura_load_github_token
