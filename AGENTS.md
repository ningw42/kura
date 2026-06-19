# Repository overview for AI agents

This is **kura** — a personal Nix flake holding packages that aren't in nixpkgs, or whose nixpkgs version is stale. It exists to back another flake (the owner's nixos/home-manager config) without forking nixpkgs.

## Layout

```
flake.nix              # outputs: packages, overlays, devShells, checks, formatter, apps.update
shell.nix              # runtime deps for the update runner (NOT for `nix develop`)
matrix.nix             # CI build list + GHA matrix expansion (mirror of garnix.yaml; sole source of truth post-Garnix)
pkgs/
  default.nix          # callPackage-wires every package into one attrset
  <pkg-name>/
    default.nix        # the derivation
    [package-lock.json | other lockfiles]
  _update/             # shared updater library (see "Updating packages")
    run.sh             # the shared driver
    hooks.sh           # named hook functions (sync-go-builder, regen-npm-lockfile)
    runner.nix         # wraps nixpkgs' maintainers/scripts/update.nix
treefmt.nix            # nixfmt + yamlfmt config
git-hooks.nix          # pre-commit hooks (treefmt, convco, etc.)
garnix.yaml            # tells Garnix which attrs to build & cache (duplicated in matrix.nix for the GHA pipeline)
.github/workflows/
  build-and-push-to-caches.yml  # mirror pipeline: expands matrix.nix into a build matrix, pushes to kura.cachix.org + self-hosted Attic
```

## Building a package

```bash
nix build .#<pkg-name>            # builds the derivation
nix flake check --no-build        # evaluates flake; does not build
```

`packages.<system>` is exposed for `x86_64-linux` and `aarch64-darwin`. Garnix only builds the Linux set; Darwin attrs evaluate but aren't cached unless added to `garnix.yaml`.

## Overlay shape

`overlays.default` exposes every kura package under a single `kura` attribute (`pkgs.kura.fzf`, `pkgs.kura.skim`, …) rather than merging them in at top level. It's a **pointer overlay**: the values are `self.packages.${system}` verbatim, so consumers get the exact cached store path regardless of their own nixpkgs pin.

It nests under `kura` on purpose. Overriding a top-level name (e.g. `fzf`) would join the consumer's fixpoint, so every nixpkgs package that resolves that name through `callPackage` — `zoxide` bakes `fzf`'s store path into its binary, for one — would re-evaluate, change hash, and miss `cache.nixos.org`. Nesting keeps the rest of nixpkgs bit-identical and cached; consumers opt into a kura build by name. The full rationale (and tradeoffs) live in the comment on `overlays.default` in `flake.nix`.

Consequence for package authors: kura packages can't compose through the consumer's `final`/`prev`. If one kura package needs another, wire it inside `pkgs/default.nix` directly (the `pkgs` arg there is kura's own pinned nixpkgs — see `pkgsFor` in `flake.nix`).

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
| `sync-go-builder` | `sync-go-builder:<owner>/<repo>:<tag-prefix>` | Read upstream `go.mod`, bump pinned `buildGoNNModule`. No-op if `default.nix` uses unpinned `buildGoModule`. | telepush, sing-box, koito |
| `regen-npm-lockfile` | `regen-npm-lockfile:<owner>/<repo>:<tag-prefix>[:<flags>]` | Clone the new tag, strip `scripts`, pin direct deps, regenerate `package-lock.json` with npm 10. Pre-hook only. Tolerates upstream repos with no lockfile (pin step no-ops). `<flags>` (substring-matched): `legacy-peer-deps` → pass `--legacy-peer-deps`; `omit-dev` → drop `devDependencies` for a production-only lockfile (matching `default.nix` must strip them in `postPatch` so `npm ci` stays in sync). | brave-search-mcp-server, multi-scrobbler, pi-mcp-adapter |
| `regen-yarn-berry-missing-hashes` | `regen-yarn-berry-missing-hashes:<owner>/<repo>:<tag-prefix>:<path-to-yarn.lock>` | Fetch upstream `yarn.lock` and regenerate `missing-hashes.json` via `yarn-berry-fetcher missing-hashes`. Pre-hook only — must run before `nix-update` because the `offlineCache` output hash depends on both files. | koito |

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
- **Single-platform default**: only `x86_64-linux` is built by default. `aarch64-darwin` is supported for evaluation but only specific packages get built and cached. To opt a Darwin package in, add `packages.aarch64-darwin.<name>` to both `garnix.yaml` (`builds.include`) and `matrix.nix` (`includes`) — Garnix and the GitHub Actions pipeline read them separately and the two lists are hand-kept in sync until Garnix is retired.
- **Source pinning — `rev` vs `tag`**: pin `fetchFromGitHub` sources with `rev = "v${version}"`, **not** `tag = "v${version}"`, even though `tag` is the more modern/declarative nixpkgs idiom. Reason: `fetchFromGitHub` normalizes `tag` to `src.rev = "refs/tags/v…"`, but `nix-update` discovers the upstream version as the *bare* tag (`v…`). The two never compare equal, so nix-update concludes the rev "changed" on **every** run and re-fetches all dependency hashes (`cargoHash`/`vendorHash`/`npmDeps`/`pnpmDeps`/…) even when the version is unchanged — turning a no-op update into a full re-vendor (≈10 min for `byokey`'s cargo tree). Using `rev` keeps both sides equal, so hashes are only recomputed on a real version bump. Consequences: with `rev`, `src.tag` is `null` and `src.rev` is the bare tag — don't reference `src.tag` in `meta.changelog`/`ldflags` (use `"v${version}"`). The source `hash` is content-addressed and identical either way, so switching never changes the fetched output. This is not fixable by bumping `nix-update`: as of upstream master the comparison is still `old_rev_tag = package.rev or package.tag` (prefers the `refs/tags/` rev), so the only ways to keep `tag` would be patching nix-update (flip it to `package.tag or package.rev`) or a custom version-equality pre-check — both more machinery than just using `rev`.
- **Avoid creating new docs files** unless explicitly asked. This file (AGENTS.md) and README.md are the canonical entry points; CLAUDE.md is a one-line shim that includes this file.

## Pitfalls observed

- `nix-update` reads `GITHUB_TOKEN` from env but does **not** read `~/.config/nix/access-tokens.conf` (only `nix-prefetch-github` does). The `apps.update` shell wrapper in `flake.nix` bridges the file to the env var before invoking the runner, so every downstream `nix-update` call (both shared-driver and plain `nix-update-script` ones) inherits it. Without that bridge, version-discovery hits 60/hr unauthenticated; with it, 5000/hr.
- `pkgs/_update/run.sh` lives in the nix store at runtime; `$BASH_SOURCE` points there. The flake root is `$PWD` (the runner cd's there before invoking).
- The runner leaves `<pname>.log` files in the cwd; `.gitignore` already covers `*.log`.
- The nixpkgs runner wraps every invocation in `nix-shell ${nixpkgs_root}/shell.nix --run …`. That's why `shell.nix` at the repo root is required, even though humans use `nix develop` instead.
