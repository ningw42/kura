# kura

A personal Nix flake of packages that aren't in nixpkgs, or whose nixpkgs version lags behind upstream. Cached on [Garnix](https://garnix.io/) so consumers don't have to rebuild from source.

## What's in here

```
brave-search-mcp-server   clash-premium    fzf            koito
lazygit                   litellm          multi-scrobbler
router-maestro            sing-box-alpha (1.14 alpha)     skim
smartthings-soundbar (Home Assistant)      subsonic-now-playing-overlay
telepush                  transmissionic   trguing
```

See `pkgs/<name>/default.nix` for each derivation.

## Using it from another flake

```nix
{
  inputs.kura.url = "github:ningw42/kura";

  outputs = { self, nixpkgs, kura, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        ({ pkgs, ... }: {
          # Either as an overlay (every kura package becomes a top-level attr):
          nixpkgs.overlays = [ kura.overlays.default ];
          environment.systemPackages = [ pkgs.skim pkgs.telepush ];

          # Or pull packages directly:
          # environment.systemPackages = [ kura.packages.${pkgs.system}.skim ];
        })
      ];
    };
  };
}
```

The flake exposes `packages.x86_64-linux.*` and `packages.aarch64-darwin.*`. Garnix only caches Linux by default; Darwin works but builds from source unless added to `garnix.yaml`.

## Updating packages

Every updatable package declares its own `passthru.updateScript`. A single command drives the lot:

```bash
nix run .#update                            # update every package in parallel
nix run .#update -- --package telepush      # just one
nix run .#update -- --skip-prompt           # don't ask before starting
nix run .#update -- --commit                # one commit per package, auto-generated message
```

What happens under the hood: `pkgs/_update/runner.nix` wraps nixpkgs' standard `maintainers/scripts/update.nix` and points it at our `packages.<system>` attrset. For each package, it runs `nix-update` (plus any pre/post hooks declared in `default.nix`), updates version + hashes in place, and reports per-package success/failure.

### A few things to know

- **Authenticated GitHub API.** The `apps.update` shell wrapper in `flake.nix` reads `~/.config/nix/access-tokens.conf` and exports `GITHUB_TOKEN` so `nix-update` doesn't get rate-limited at 60/hr. Make sure that file exists (it's the same one `nix.settings.access-tokens` writes).
- **Already-current packages are a no-op.** The driver short-circuits before doing real work if the upstream version matches what's checked in.
- **Pre/post hooks.** A few packages need work that `nix-update` can't do on its own: bumping `buildGoNNModule` to match upstream `go.mod`, regenerating an npm lockfile with npm 10 because upstream's npm 11 lockfile drops `resolved` URLs, etc. These live as named functions in `pkgs/_update/hooks.sh` and are wired declaratively in each package's `default.nix`.

### When an update fails

The runner uses `--keep-going`, so one failure won't stop the others. Failures are printed at the end with their error log. Common reasons:

- **Upstream switched a lockfile format** (e.g. yarn classic → yarn berry). Fix the package's `default.nix` to use the new tooling; the updater itself is fine.
- **Upstream introduced a new build dependency.** Add it to the derivation's inputs.
- **Transient GitHub API hiccup.** Re-run the single failing package: `nix run .#update -- --package <name> --skip-prompt`.

After an update, build the affected package to confirm hashes are correct:

```bash
nix build .#<pkg-name>
```

## Adding a new package

1. Create `pkgs/<name>/default.nix`.
2. Wire it into `pkgs/default.nix` (use `callPackage` or `callPythonPackage`).
3. Add `passthru.updateScript`:
   - **Simple case**: `nix-update-script { extraArgs = [ "--flake" "--use-github-releases" ]; };`
   - **Needs custom work**: see existing examples in `pkgs/telepush/default.nix` (post-hook), `pkgs/brave-search-mcp-server/default.nix` (pre-hook), `pkgs/koito/default.nix` (multi-attr + post-hook).
4. `nix build .#<name>` to verify it builds.
5. `nix run .#update -- --package <name> --skip-prompt` to verify the updater is a no-op at the current version.

`AGENTS.md` has the full decision tree and a list of available hooks.

## Local development

```bash
nix develop          # drops you into a shell with treefmt + pre-commit hooks installed
nix fmt              # format everything via treefmt (nixfmt + yamlfmt)
nix flake check      # evaluate everything, run formatter + pre-commit checks
```

The first `nix develop` after cloning or after editing `git-hooks.nix` will install the pre-commit hooks. Pre-commit enforces conventional commit messages (`convco`), formatting, and a few sanity checks (no merge conflicts, no private keys, trimmed whitespace).

## Caching

Builds happen on Garnix for `master`. Substituter and key:

```nix
nix.settings = {
  substituters = [ "https://cache.garnix.io" ];
  trusted-public-keys = [ "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" ];
};
```

`garnix.yaml` controls what gets built. To add Darwin builds for a specific package, add `packages.aarch64-darwin.<name>` under `builds.include`.

## Repo layout

See `AGENTS.md` for a tree and a quick tour. Short version: derivations live in `pkgs/<name>/`, the shared updater library is `pkgs/_update/`, and `flake.nix` ties everything together.
