# kura

A personal Nix flake of packages that aren't in nixpkgs, or whose nixpkgs version lags behind upstream. Cached on [Cachix](https://www.cachix.org/) so consumers don't have to rebuild from source.

## What's in here

✅ marks a platform the package is **prebuilt and cached** for; a blank cell means no prebuilt artifact, so supported packages build from source. Every package attribute is exposed for both systems regardless — the table only reflects what's cached (see [Build validation and caching](#build-validation-and-caching)).

| Package | x86_64-linux | aarch64-darwin |
|---|:-:|:-:|
| brave-search-mcp-server | ✅ | |
| clash-premium | ✅ | |
| copilotd | ✅ | |
| fzf | ✅ | ✅ |
| koito | ✅ | |
| lazygit | ✅ | ✅ |
| litellm | ✅ | |
| moor | ✅ | ✅ |
| multi-scrobbler | ✅ | |
| pi-distribution | ✅ | ✅ |
| sing-box | ✅ | |
| skim | ✅ | ✅ |
| smartthings-soundbar | ✅ | |
| subsonic-now-playing-overlay | ✅ | |
| telepush | ✅ | |
| transmissionic | ✅ | |
| trguing | ✅ | |
| zashboard | ✅ | |

See `pkgs/<name>/default.nix` for each derivation.

## Using it from another flake

```nix
{
  inputs.kura.url = "github:ningw42/kura";

  outputs = { self, nixpkgs, kura, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        ({ pkgs, ... }: {
          # Either as an overlay (packages land under pkgs.kura.*):
          nixpkgs.overlays = [ kura.overlays.default ];
          environment.systemPackages = [ pkgs.kura.skim pkgs.kura.telepush ];

          # Or pull packages directly:
          # environment.systemPackages = [ kura.packages.${pkgs.system}.skim ];
        })
      ];
    };
  };
}
```

The flake exposes `packages.x86_64-linux.*` and `packages.aarch64-darwin.*`. Every Linux package is cached; on Darwin, only the checkmarked packages above are cached. Other supported Darwin packages build from source unless added to `matrix.nix`.

## Updating packages

Each updatable package declares `passthru.updateScript`; the flake app runs them in parallel:

```bash
nix run .#update                            # update every updatable package in parallel
nix run .#update -- --package telepush      # just one
nix run .#update -- --max-workers 4         # cap parallel update jobs
nix run .#update -- --skip-prompt           # don't ask before starting
nix run .#update -- --commit                # one commit per package, auto-generated message
```

The app delegates to nixpkgs' update runner, keeps going after individual failures, and prints their logs at the end. Re-run one failure with `nix run .#update -- --package <name> --skip-prompt`.

GitHub-backed updates use `GITHUB_TOKEN`; the app imports it from `~/.config/nix/access-tokens.conf`, the same file written by `nix.settings.access-tokens`. Already-current packages are no-ops.

After an update, verify the affected package with `nix build .#<pkg-name>`. Updater patterns, hooks, and troubleshooting are documented in [AGENTS.md](AGENTS.md#updating-packages).

## Adding a new package

Follow the checklist in [AGENTS.md](AGENTS.md#adding-a-new-package). It covers package wiring, updater selection, the build check, and the updater no-op check.

## Local development

```bash
nix develop          # drops you into a shell with treefmt + pre-commit hooks installed
nix fmt              # format everything via treefmt (nixfmt + yamlfmt)
nix flake check      # evaluate everything, run formatter + pre-commit checks
```

The first `nix develop` after cloning installs the pre-commit hooks; re-run it after changing flake inputs or `git-hooks.nix`. Pre-commit enforces conventional commit messages (`convco`), formatting, and a few sanity checks (no merge conflicts, no private keys, trimmed whitespace).

## Build validation and caching

`matrix.nix` is the source of truth for two selective GitHub Actions workflows:

- **PR validation** compares configured outputs with the pull request's base commit, builds changed outputs without a writable cache, and publishes nothing. Its stable `Package build validation` result is suitable for branch protection.
- **Cache publishing** compares outputs with the latest successful cache run, then pushes changed closures to Cachix and Attic. Failed or canceled runs therefore cannot leave later changes unpublished.

Selection compares exact Nix `outPath`s rather than inferring affected packages from source paths. Manual runs and events without a usable baseline build the full matrix.

Each successful publishing run is a complete cache checkpoint: unchanged paths were covered by an earlier successful run, and changed paths are built and pushed. If either cache is purged independently, use a manual dispatch to repopulate the full matrix.

To consume the public cache, add the substituter to your Nix config:

```nix
nix.settings = {
  substituters = [
    "https://kura.cachix.org"
  ];
  trusted-public-keys = [
    "kura.cachix.org-1:nOM/8zHJpVt4prp0lyU3LQNsKPmo37BFiOw8q+Gm8TQ="
  ];
};
```

To cache a package on Darwin, add `packages.aarch64-darwin.<name>` to its `includes` list in `matrix.nix`.

### Setting up the Cachix + Attic pipeline (one-time)

1. Create the `kura` cache on <https://app.cachix.org>, generate a write auth token, and add it as the `CACHIX_AUTH_TOKEN` repo secret.
2. Add the Attic server URL and cache name as the `ATTIC_ENDPOINT` and `ATTIC_CACHE` repo secrets.
3. Mint a push+pull token on the Attic server scoped to that cache and add it as the `ATTIC_TOKEN` repo secret.
4. Copy the Cachix public key into the `trusted-public-keys` snippet above (and update this README).
