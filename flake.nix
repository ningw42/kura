{
  description = "Ning's personal Nix package collection (kura). Cached via Cachix and Attic.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      git-hooks,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forSupportedSystems = nixpkgs.lib.genAttrs supportedSystems;
      # Plain nixpkgs per system. Used to build every output (packages,
      # checks, devShells, ...) against kura's *own* pinned nixpkgs, so the
      # cached store paths exposed via `overlays.default` stay
      # consumer-agnostic.
      pkgsFor = forSupportedSystems (system: import nixpkgs { inherit system; });

      treefmtEval = forSupportedSystems (
        system: treefmt-nix.lib.evalModule pkgsFor.${system} ./treefmt.nix
      );

      gitHooksCheck = forSupportedSystems (
        system:
        git-hooks.lib.${system}.run {
          src = ./.;
          hooks = import ./git-hooks.nix {
            pkgs = pkgsFor.${system};
            treefmtWrapper = treefmtEval.${system}.config.build.wrapper;
          };
        }
      );
    in
    {
      # Overlay consumers add to their own pkgs. It exposes every kura package
      # under a single `kura` attribute — `pkgs.kura.fzf`, `pkgs.kura.skim`, … —
      # rather than merging them in at top level.
      #
      # Why nest instead of overriding top-level names: the overlay joins the
      # consumer's package-set fixpoint, so a top-level `fzf = <kura fzf>`
      # wouldn't merely shadow the name — every nixpkgs package that resolves
      # `fzf` through `callPackage` (e.g. zoxide, which bakes fzf's store path
      # into its own binary) would re-evaluate against kura's fzf, change hash,
      # and miss cache.nixos.org, forcing a local rebuild. Nesting under `kura`
      # leaves top-level names untouched, so the rest of nixpkgs stays
      # bit-identical and cached; consumers opt into a kura build explicitly by
      # reaching for `pkgs.kura.*`.
      #
      # This is also a "pointer overlay": the values are the pre-built store
      # paths from `self.packages.${system}`, evaluated against kura's own
      # pinned nixpkgs (see `pkgsFor` above). That keeps each derivation hash
      # identical to what the kura caches built, so consumers hit the binary
      # cache even when their own nixpkgs pin differs from ours.
      #
      # Tradeoffs:
      #   - Kura packages don't transparently substitute for their nixpkgs
      #     namesakes; reference them by `pkgs.kura.<name>`.
      #   - Consumers can't override deps via `pkgs.kura.foo.override { ... }` —
      #     the path is sealed.
      #   - Kura packages can't compose with each other through the consumer's
      #     `final`/`prev`. Compose inside `pkgs/default.nix` instead.
      #   - May duplicate libc / openssl / ... in the closure when the
      #     consumer's nixpkgs pin differs from ours. Acceptable for a personal
      #     package set; the cache-hit win dominates.
      overlays.default = _final: prev: {
        kura = self.packages.${prev.stdenv.hostPlatform.system} or { };
      };

      # Per-system packages. Exposed for both supportedSystems so consumers
      # on either platform can pull them. The cache pipeline decides separately
      # (in matrix.nix) which of these to actually build and cache.
      packages = forSupportedSystems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        import ./pkgs { inherit pkgs; }
      );

      checks = forSupportedSystems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        {
          formatting = treefmtEval.${system}.config.build.check self;
          pre-commit-check = gitHooksCheck.${system};
          updater = pkgs.runCommand "kura-updater-tests" { } ''
            KURA_SOURCE_ROOT=${./.} ${pkgs.bash}/bin/bash ${./pkgs/_update/tests.sh}
            touch "$out"
          '';
        }
      );

      formatter = forSupportedSystems (system: treefmtEval.${system}.config.build.wrapper);

      # `nix run .#update [-- --package <name>] [--commit] [--max-workers N]`
      # walks every kura package with a passthru.updateScript and runs them
      # in parallel via nixpkgs' maintainers/scripts/update.nix. With no
      # --package the runner walks all packages.
      #
      # Translates user-friendly --foo bar args to nix-shell's --arg/--argstr
      # form expected by update.nix. `--impure` is required because the
      # runner re-imports this flake.
      apps = forSupportedSystems (
        system:
        let
          pkgs = pkgsFor.${system};
          updateApp = pkgs.writeShellApplication {
            name = "update";
            runtimeInputs = [
              pkgs.nix
              pkgs.git
            ];
            text = ''
              # Bridge ~/.config/nix/access-tokens.conf -> GITHUB_TOKEN so every
              # downstream nix-update call (both shared-driver and plain
              # nix-update-script ones) hits the 5000/hr authenticated limit
              # instead of 60/hr. nix-update itself doesn't read the file.
              if [[ -z "''${GITHUB_TOKEN:-}" && -f "$HOME/.config/nix/access-tokens.conf" ]]; then
                GITHUB_TOKEN=$(sed -n 's/.*github\.com=\([^ ]*\).*/\1/p' \
                  "$HOME/.config/nix/access-tokens.conf")
                export GITHUB_TOKEN
              fi
              args=(
                --argstr flakePath "${toString ./.}"
                --argstr system "${system}"
                --argstr keep-going true
              )
              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --package)
                    # update.nix's `package` arg is mutually exclusive with `path`,
                    # so we scope it manually to our overlay attr.
                    args+=(--argstr package "kuraPackages.$2"); shift 2 ;;
                  --maintainer|--path|--order)
                    args+=(--argstr "''${1#--}" "$2"); shift 2 ;;
                  --max-workers)
                    args+=(--arg max-workers "$2"); shift 2 ;;
                  --commit|--skip-prompt|--keep-going)
                    # update.nix compares these as strings (`== "true"`), not booleans.
                    args+=(--argstr "''${1#--}" true); shift ;;
                  --no-commit|--no-skip-prompt|--no-keep-going)
                    args+=(--argstr "''${1#--no-}" false); shift ;;
                  *)
                    echo "unknown arg: $1" >&2; exit 2 ;;
                esac
              done
              exec nix-shell --impure ${./pkgs/_update/runner.nix} "''${args[@]}"
            '';
          };
        in
        {
          update = {
            type = "app";
            program = "${updateApp}/bin/update";
          };
        }
      );

      # devShell: provides treefmt and formatter programs.
      # shellHook installs git pre-commit hooks via git-hooks.nix.
      # Run `nix develop` once to install hooks; re-run after flake input or hook changes.
      devShells = forSupportedSystems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            name = "kura";
            inherit (gitHooksCheck.${system}) shellHook;
            buildInputs = gitHooksCheck.${system}.enabledPackages;
            packages = [
              treefmtEval.${system}.config.build.wrapper
            ]
            ++ (builtins.attrValues treefmtEval.${system}.config.build.programs);
          };
        }
      );
    };
}
