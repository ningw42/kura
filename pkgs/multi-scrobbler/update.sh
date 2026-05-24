#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-update jq curl prefetch-npm-deps git nodejs_22
# Usage: ./update.sh [--version <X>]
# Defaults to the latest GitHub release.
#
# nix-update handles version + src.hash + npmDepsHash.
# Pre-step: regenerate package-lock.json with npm 10 because the upstream
# lockfile (npm 11) omits `resolved` URLs for transitive deps, breaking the
# Nix npm deps fetcher. We must regen BEFORE nix-update so the npmDepsHash
# it computes reflects our patched lockfile (postPatch copies it into src).

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FILE="$HERE/default.nix"
FLAKE_ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"

TOKEN_FILE="$HOME/.config/nix/access-tokens.conf"
if [[ -z "${GITHUB_TOKEN:-}" && -f "$TOKEN_FILE" ]]; then
  GITHUB_TOKEN=$(sed -n 's/.*github\.com=\([^ ]*\).*/\1/p' "$TOKEN_FILE")
  export GITHUB_TOKEN
fi

OLD_VERSION=$(grep 'version = ' "$FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')

# Determine the target version up front (need it for the lockfile regen step,
# which has to run BEFORE nix-update computes npmDepsHash).
NEW_VERSION=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--version" ]]; then
    NEW_VERSION="$arg"
  fi
  case "$arg" in
    --version=*) NEW_VERSION="${arg#--version=}" ;;
  esac
  prev="$arg"
done
if [[ -z "$NEW_VERSION" ]]; then
  CURL_OPTS=(-s)
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_OPTS+=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi
  NEW_VERSION=$(curl "${CURL_OPTS[@]}" https://api.github.com/repos/FoxxMD/multi-scrobbler/releases/latest \
    | jq -r .tag_name)
  if [[ -z "$NEW_VERSION" || "$NEW_VERSION" == "null" ]]; then
    echo "Error: could not determine latest version" >&2
    exit 1
  fi
fi

if [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
  echo "Already at version $NEW_VERSION"
  exit 0
fi

echo "Updating multi-scrobbler: $OLD_VERSION -> $NEW_VERSION"

# Regenerate lockfile with npm 10 (Node 22).
# Strip scripts to avoid build/format steps during lockfile generation, and
# pin direct deps to the exact versions upstream resolved, so regeneration
# doesn't drift to newer minor/alpha releases (e.g. 5.0.0-alpha.2 -> alpha.8
# removed `applyDelta`, breaking the build).
echo "Regenerating lockfile..."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone --depth 1 --branch "$NEW_VERSION" https://github.com/FoxxMD/multi-scrobbler.git "$WORK/source" 2>&1 | tail -1
cd "$WORK/source"
node -e "
  const fs = require('fs');
  const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  delete pkg.scripts;
  const lock = JSON.parse(fs.readFileSync('package-lock.json', 'utf8'));
  for (const section of ['dependencies', 'devDependencies']) {
    if (!pkg[section]) continue;
    for (const name of Object.keys(pkg[section])) {
      const entry = lock.packages && lock.packages['node_modules/' + name];
      if (entry && entry.version) pkg[section][name] = entry.version;
    }
  }
  fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
"
rm -f package-lock.json
npm install --package-lock-only --ignore-scripts --legacy-peer-deps 2>&1 | tail -1
cp "$WORK/source/package-lock.json" "$HERE/package-lock.json"

# Hand off to nix-update for version + src.hash + npmDepsHash.
# postPatch copies our patched lockfile into src, so npmDepsHash reflects it.
(cd "$FLAKE_ROOT" && nix-update --flake --use-github-releases --version "$NEW_VERSION" multi-scrobbler)

echo ""
echo "Updated $FILE and package-lock.json to version $NEW_VERSION"
echo "Verify with: nix build .#multi-scrobbler"
