# Sourceable. Hook functions invoked by run.sh.
#
# Each function reads KURA_PKG_DIR and KURA_VERSION from the environment
# (set by run.sh) and takes hook-spec parameters as positional arguments.
#
# Hook spec format passed by default.nix: `name:arg1:arg2[:arg3...]`
# run.sh splits on `:`, dispatches by `name`, and forwards the rest.

# sync-go-builder:<owner>/<repo>:<tag-prefix>
# Read upstream go.mod and bump the pinned `buildGoNNModule` in default.nix.
# Unpinned `buildGoModule` is left alone (intentional: roll forward with nixpkgs).
sync_go_builder() {
  local owner_repo="$1" tag_prefix="${2:-}"
  local file="$KURA_PKG_DIR/default.nix"

  local old_builder
  old_builder=$(grep -oP 'buildGo\d+Module' "$file" | head -1 || true)
  if [[ -z "$old_builder" ]]; then
    echo "[sync-go-builder] $file uses unpinned buildGoModule; nothing to sync."
    return 0
  fi

  echo "[sync-go-builder] Inspecting upstream go.mod for Go version..."
  local go_line
  go_line=$(curl -sL "https://raw.githubusercontent.com/${owner_repo}/${tag_prefix}${KURA_VERSION}/go.mod" \
    | awk '/^go [0-9]+\.[0-9]+/ { print $2; exit }')
  if [[ -z "$go_line" ]]; then
    echo "[sync-go-builder] ERROR: could not read 'go <version>' from upstream go.mod" >&2
    return 1
  fi

  local major_minor new_builder
  major_minor=$(echo "$go_line" | awk -F. '{ print $1 $2 }')
  new_builder="buildGo${major_minor}Module"
  echo "[sync-go-builder] Upstream requires Go $go_line -> $new_builder"

  if [[ "$old_builder" == "$new_builder" ]]; then
    return 0
  fi
  if ! nix eval --impure --expr "(import <nixpkgs> {}).${new_builder}.name" >/dev/null 2>&1; then
    echo "[sync-go-builder] ERROR: $new_builder is not available in nixpkgs." >&2
    return 1
  fi
  echo "[sync-go-builder] Switching: $old_builder -> $new_builder"
  sed -i "s/\\b${old_builder}\\b/${new_builder}/g" "$file"
}

# regen-npm-lockfile:<owner>/<repo>:<tag-prefix>[:legacy-peer-deps]
# Clone the new tag, strip scripts, pin direct deps to lock-resolved versions,
# regenerate package-lock.json with npm 10 (Node 22) so transitive deps have
# `resolved` URLs, copy result to $KURA_PKG_DIR/package-lock.json.
#
# Must run BEFORE nix-update so npmDepsHash computation reflects the patched
# lockfile (postPatch in default.nix copies it into src).
regen_npm_lockfile() {
  local owner_repo="$1" tag_prefix="${2:-}" extra="${3:-}"
  local legacy_flag=""
  [[ "$extra" == "legacy-peer-deps" ]] && legacy_flag="--legacy-peer-deps"

  echo "[regen-npm-lockfile] Cloning ${owner_repo}@${tag_prefix}${KURA_VERSION}..."
  local work
  work=$(mktemp -d)
  trap "rm -rf '$work'" RETURN

  git clone --depth 1 --branch "${tag_prefix}${KURA_VERSION}" \
    "https://github.com/${owner_repo}.git" "$work/source" 2>&1 | tail -1
  ( cd "$work/source"
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
    npm install --package-lock-only --ignore-scripts $legacy_flag 2>&1 | tail -1
  )
  cp "$work/source/package-lock.json" "$KURA_PKG_DIR/package-lock.json"
  echo "[regen-npm-lockfile] Wrote $KURA_PKG_DIR/package-lock.json"
}
