# Repository overview for AI agents

This is **kura** (蔵, "storehouse") — a personal Nix flake holding packages that aren't in nixpkgs, or whose nixpkgs version is stale. It exists to back another flake (the owner's nixos/home-manager config) without forking nixpkgs.

## Layout

```
flake.nix              # outputs: packages, overlays, devShells, checks, formatter, apps.update
shell.nix              # runtime deps for the update runner (NOT for `nix develop`)
pkgs/
  default.nix          # callPackage-wires every package into one attrset
  <pkg-name>/
    default.nix        # the derivation
    [package-lock.json | other lockfiles]
  _update/             # shared updater library (see "Updating packages")
    run.sh             # the shared driver
    hooks.sh           # named hook functions (sync-go-builder, regen-npm-lockfile)
    token.sh           # loads GITHUB_TOKEN from ~/.config/nix/access-tokens.conf
    runner.nix         # wraps nixpkgs' maintainers/scripts/update.nix
treefmt.nix            # nixfmt + yamlfmt config
git-hooks.nix          # pre-commit hooks (treefmt, convco, etc.)
garnix.yaml            # tells Garnix which attrs to build & cache (x86_64-linux only by default)
```

## Building a package

```bash
nix build .#<pkg-name>            # builds the derivation
nix flake check --no-build        # evaluates flake; does not build
```

`packages.<system>` is exposed for `x86_64-linux` and `aarch64-darwin`. Garnix only builds the Linux set; Darwin attrs evaluate but aren't cached unless added to `garnix.yaml`.

## Updating packages

Every updatable package declares `passthru.updateScript`. The entry point is a flake app:

```bash
nix run .#update                            # walk all packages, update in parallel
nix run .#update -- --package <name>        # one package
nix run .#update -- --skip-prompt           # don't ask for confirmation
nix run .#update -- --commit                # produce one commit per package
```

The app wraps nixpkgs' `maintainers/scripts/update.nix` via `pkgs/_update/runner.nix`, which scopes the walk to our packages via a `kuraPackages` overlay attr. `shell.nix` at the repo root provides the runtime tools the runner injects (`nix-update`, `jq`, `curl`, `prefetch-npm-deps`, `nodejs_22`, etc.) — humans should *not* use `shell.nix`; `nix develop` drops you into the proper devShell.

### Update pattern decision tree

When wiring `passthru.updateScript` on a package, pick the simplest pattern that works:

1. **Plain GitHub release, no custom work** → `nix-update-script { extraArgs = [ "--flake" "--use-github-releases" ]; }`. Pass extra nix-update flags through `extraArgs` (e.g. `--version-regex`). Examples: `skim`, `router-maestro`, `litellm`.
2. **Needs pre- or post-update steps** → use the shared driver:
   ```nix
   passthru.updateScript = [
     ../_update/run.sh
     "--attr" "<attrpath>"           # repeatable; defaults to UPDATE_NIX_ATTR_PATH
     "--use-github-releases"         # forwarded to nix-update
     "--pre-hook"  "<hook-spec>"     # repeatable; runs before nix-update
     "--post-hook" "<hook-spec>"     # repeatable; runs after nix-update
   ];
   ```
   `--pre-hook` and `--post-hook` are **driver flags**, not `nix-update` flags. Hook spec format: `name:arg1:arg2[:arg3...]`, parsed in `pkgs/_update/run.sh` and dispatched to functions in `pkgs/_update/hooks.sh`.

### Hooks available today (`pkgs/_update/hooks.sh`)

| name | spec | what it does | used by |
|---|---|---|---|
| `sync-go-builder` | `sync-go-builder:<owner>/<repo>:<tag-prefix>` | Read upstream `go.mod`, bump pinned `buildGoNNModule`. No-op if `default.nix` uses unpinned `buildGoModule`. | telepush, sing-box-alpha, koito |
| `regen-npm-lockfile` | `regen-npm-lockfile:<owner>/<repo>:<tag-prefix>[:legacy-peer-deps]` | Clone the new tag, strip `scripts`, pin direct deps, regenerate `package-lock.json` with npm 10. Pre-hook only. | brave-search-mcp-server, multi-scrobbler |

To add a new hook: write the function in `pkgs/_update/hooks.sh` (reads `$KURA_PKG_DIR` and `$KURA_VERSION` from env), then add a `case` branch in `_run_hook` in `pkgs/_update/run.sh`.

### Multi-attr packages (e.g. koito)

When one package has multiple sub-derivations with their own hashes (backend + frontend, native + electron, etc.), pass `--attr` multiple times. The driver runs `nix-update` once per attr, pinning subsequent calls to the version the first one resolved:

```nix
passthru.updateScript = [
  ../_update/run.sh
  "--attr" "koito.backend"     # shared version + src.hash + vendorHash
  "--attr" "koito.frontend"    # yarnOfflineCache.outputHash (nix-update native)
  "--use-github-releases"
  "--post-hook" "sync-go-builder:gabehf/koito:v"
];
```

Note: `nix-update` natively handles `yarnOfflineCache`, `npmDeps`, `pnpmDeps`, `cargoHash`, `vendorHash`, `mvnHash`, etc. — no custom hook needed. Just point `--attr` at the attribute that exposes the hash. See `nix_update/eval.nix` upstream for the full list.

### Suppressing the runner for a package

Some derivations (e.g. `buildHomeAssistantComponent`) inherit a default `passthru.updateScript` that doesn't work for our flake, *or* have a `pname` containing characters the runner chokes on (e.g. `<owner>/<domain>` for HA components — the runner tries to write `<pname>.log` and fails on the slash). Override to `null`:

```nix
passthru.updateScript = null;
```

This skips the package entirely. The runner filters out null `updateScript`s before scheduling.

## Adding a new package

1. `mkdir pkgs/<name>` and write `pkgs/<name>/default.nix`.
2. Add an entry to `pkgs/default.nix` (use `callPackage` or `callPythonPackage` as appropriate).
3. Decide an update strategy and wire `passthru.updateScript` per the decision tree above.
4. Run `nix build .#<name>` to make sure it builds.
5. Run `nix run .#update -- --package <name> --skip-prompt` to make sure the updater is a clean no-op (or a sensible update).

## Conventions

- **Commit messages**: conventional commits, enforced by `convco` in pre-commit hooks. Common types here: `feat(<pkg>)`, `build(<pkg>)`, `refactor(...)`, `chore(...)`. Scope is usually the package name or a subsystem (`flake`, `update`, `gitignore`). See recent `git log --oneline` for the local idiom.
- **No Co-Authored-By trailers.** The owner removes them when amending — don't add them.
- **Formatting**: `nix fmt` runs treefmt (nixfmt + yamlfmt). Also runs via pre-commit. If pre-commit reformats during a commit, just re-stage and re-commit.
- **Single-platform default**: only `x86_64-linux` is cached by Garnix. `aarch64-darwin` is supported for evaluation but only specific packages get cached (opt in via `garnix.yaml`).
- **Avoid creating new docs files** unless explicitly asked. This file (AGENTS.md) and README.md are the canonical entry points; CLAUDE.md is a one-line shim that includes this file.

## Pitfalls observed

- `nix-update` reads `GITHUB_TOKEN` from env but does **not** read `~/.config/nix/access-tokens.conf` (only `nix-prefetch-github` does). `pkgs/_update/token.sh` bridges the file to the env var. Without it, version-discovery hits 60/hr unauthenticated; with it, 5000/hr.
- `pkgs/_update/run.sh` lives in the nix store at runtime; `$BASH_SOURCE` points there. The flake root is `$PWD` (the runner cd's there before invoking).
- The runner leaves `<pname>.log` files in the cwd; `.gitignore` already covers `*.log`.
- The nixpkgs runner wraps every invocation in `nix-shell ${nixpkgs_root}/shell.nix --run …`. That's why `shell.nix` at the repo root is required, even though humans use `nix develop` instead.
