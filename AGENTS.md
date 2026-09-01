# Repository guidance for AI agents

**kura** is a personal Nix flake for packages missing from nixpkgs or lagging upstream. It backs the owner's NixOS/home-manager flake without forking nixpkgs.

## Non-obvious layout

- `flake.nix` defines packages, the pointer overlay, checks, dev shells, and `apps.update`.
- `pkgs/default.nix` wires every kura package against kura's pinned nixpkgs.
- `pkgs/_update/` contains the shared updater driver, hook implementations, and nixpkgs update-runner wrapper.
- `matrix.nix` is the source of truth for CI validation and cache publishing on each platform.
- `shell.nix` supplies runtime dependencies to nixpkgs' update runner; humans use `nix develop` instead.

## Overlay contract

`overlays.default` exposes packages under `pkgs.kura` and points directly to `self.packages.${system}`. This preserves the exact cached store paths and avoids placing kura package names in the consumer's nixpkgs fixpoint.

Before changing the overlay, read its rationale comment in `flake.nix`. Kura packages cannot compose through a consumer's `final` or `prev`; wire dependencies between kura packages explicitly in `pkgs/default.nix`.

## Package workflow

```bash
nix build .#<pkg-name>       # build one package
nix flake check --no-build   # evaluate the flake without building packages
```

Package attributes are exposed for `x86_64-linux` and `aarch64-darwin`. Linux packages are built, validated, and cached by default. To opt a Darwin package into CI and caching, add `packages.aarch64-darwin.<name>` to `matrix.nix`.

### Adding a new package

1. Create `pkgs/<name>/default.nix`.
2. Wire it into `pkgs/default.nix` with `callPackage` or `callPythonPackage`.
3. Select and configure `passthru.updateScript` using the updater rules below.
4. Run `nix build .#<name>`.
5. Run `nix run .#update -- --package <name> --skip-prompt`.

The package is complete when the build succeeds and the updater produces either a clean no-op at the current version or a sensible version update.

## Updating packages

Every updatable package declares `passthru.updateScript`. The flake app wraps nixpkgs' `maintainers/scripts/update.nix` and scopes it to kura packages:

```bash
nix run .#update                            # update all packages in parallel
nix run .#update -- --package <name>        # update one package
nix run .#update -- --skip-prompt           # skip confirmation
nix run .#update -- --commit                # commit each package separately
```

### Choose an update pattern

1. **Plain GitHub release, no custom work** — use:

   ```nix
   nix-update-script {
     extraArgs = [ "--flake" "--use-github-releases" ];
   }
   ```

   Pass other `nix-update` flags, such as `--version-regex`, through `extraArgs`.

2. **Pre- or post-update work** — use the shared driver:

   ```nix
   passthru.updateScript = [
     ../_update/run.sh
     "--attr" "<attrpath>"           # repeatable; defaults to UPDATE_NIX_ATTR_PATH
     "--use-github-releases"         # forwarded to nix-update
     "--pre-hook" "<hook-spec>"      # repeatable driver flag
     "--post-hook" "<hook-spec>"     # repeatable driver flag
   ];
   ```

   Hook specs use `name:arg1:arg2[:arg3...]`. When selecting, modifying, or adding a hook, read `pkgs/_update/hooks.sh` and `_run_hook` in `pkgs/_update/run.sh`; they are the source of truth for available names, arguments, and behavior.

### Multi-attribute packages

Pass `--attr` more than once when a package has sub-derivations with separate hashes. The driver resolves the version from the first attribute and pins later updates to it:

```nix
passthru.updateScript = [
  ../_update/run.sh
  "--attr" "koito.backend"
  "--attr" "koito.frontend"
  "--use-github-releases"
  "--pre-hook" "sync-go-builder:gabehf/koito:v"
];
```

`nix-update` natively handles common dependency hashes, including `yarnOfflineCache`, `npmDeps`, `pnpmDeps`, `cargoHash`, `vendorHash`, and `mvnHash`. Point `--attr` at the derivation exposing the hash before considering a custom hook.

### Suppress an inherited updater

Set `passthru.updateScript = null` when a derivation inherits an updater incompatible with this flake or has an unsafe `pname` such as `<owner>/<domain>`; the runner uses `pname` for log filenames. Null scripts are excluded from scheduling.

## Conventions

- **Commits:** use conventional commits. Follow recent `git log --oneline` for local types and scopes. Do not add `Co-Authored-By` trailers.
- **Formatting:** run `nix fmt` after edits; it applies nixfmt and yamlfmt. If a commit hook reformats files, re-stage them before committing again.
- **GitHub source pins:** for version tags, use `rev = "v${version}"` in `fetchFromGitHub`, not `tag`. `tag` normalizes to `refs/tags/v…` while `nix-update` discovers the bare tag, causing no-op updates to recompute dependency hashes. With `rev`, `src.tag` is null; use `"v${version}"` directly in changelogs and linker flags.
- **Documentation:** keep `README.md` and this file as the canonical entry points. Create another documentation file only when explicitly requested; `CLAUDE.md` remains a one-line shim to this file.

## Updater pitfalls

- `nix-update` reads `GITHUB_TOKEN`, not `~/.config/nix/access-tokens.conf`. The `apps.update` wrapper in `flake.nix` bridges the Nix access token into the environment.
- `pkgs/_update/run.sh` executes from the Nix store, so `$BASH_SOURCE` does not locate the checkout. The runner changes to the flake root first; use `$PWD`.
- The nixpkgs runner invokes jobs through `nix-shell ${nixpkgs_root}/shell.nix`. Keep the repository's `shell.nix` even though interactive development uses `nix develop`.
