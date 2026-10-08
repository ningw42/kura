# kura

A personal Nix flake of packages that aren't in nixpkgs, or whose nixpkgs version lags behind upstream. Cached on [Cachix](https://www.cachix.org/) so consumers don't have to rebuild from source.

## What's in here

✅ marks a platform the package is **prebuilt and cached** for; a blank cell means a supported package builds from source, and — means the package is not exposed on that platform (see [Build validation and caching](#build-validation-and-caching)).

| Package | x86_64-linux | aarch64-darwin |
|---|:-:|:-:|
| brave-search-mcp-server | ✅ | |
| clash-premium | ✅ | |
| copilotd | ✅ | |
| fzf | ✅ | ✅ |
| herdr | ✅ | ✅ |
| koito | ✅ | |
| lazygit | ✅ | ✅ |
| litellm | ✅ | |
| magpie | ✅ | — |
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

The flake exposes `packages.x86_64-linux.*` and `packages.aarch64-darwin.*`. Every Linux package is cached; on Darwin, only the checkmarked packages above are cached. Other supported Darwin packages build from source unless added to `matrix.nix`. Magpie is Linux-only and built headlessly: use `magpie serve` for the API gateway or `magpie web --gateway --no-open` for browser administration; no desktop libraries are required. Its plugins use Nix-packaged Bun, overridable with `MAGPIE_BUN`. Claude subscription providers still require a separately installed Claude Code executable and login.

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

- **PR validation** compares configured outputs with the pull request's base commit and builds changed outputs. Same-repository PRs authored by `github-actions[bot]` or whose author association is `OWNER`, `MEMBER`, or `COLLABORATOR` enable Cachix and Attic's built-in uploads. Fork PRs, other authors, and manual validation runs use public Cachix read-only and receive no cache-write credentials. Its stable `Package build validation` result is suitable for branch protection.
- **Cache publishing** runs on master pushes and manual dispatches, compares outputs with the latest successful master publishing run, and enables built-in uploads to both caches. Outputs already published by PR validation are normally substituted rather than rebuilt; merge-time changes are still built. Failed or canceled builds remain eligible for subsequent runs.

Selection compares exact Nix `outPath`s rather than inferring affected packages from source paths. Manual runs and events without a usable baseline build the full matrix.

Both workflows rely solely on the cache actions' built-in post-build hooks to publish locally built paths and their closures, including build-time dependencies. Substituted paths do not trigger uploads, so cache hits are not mirrored between caches. Attic reports upload errors as warnings rather than failing the workflow; a successful run does not guarantee that both caches contain every selected output.

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
