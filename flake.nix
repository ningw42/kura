{
  description = "Ning's personal Nix package collection (kura, 蔵). Cached via Garnix.";

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
      # Plain nixpkgs per system; kura packages currently only depend on
      # nixpkgs, so we don't apply self.overlays.default here. If a future
      # kura package needs to consume another kura package, switch the
      # overlay to use `final` (instead of `prev`) and re-apply it.
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
      # Overlay consumers add to their own pkgs to get every kura package
      # exposed as a top-level attribute (e.g. pkgs.brave-search-mcp-server).
      overlays.default = final: prev: import ./pkgs { pkgs = prev; };

      # Per-system packages. Exposed for both supportedSystems so consumers
      # on either platform can pull them. Garnix decides separately (in
      # garnix.yaml) which of these to actually build and cache.
      packages = forSupportedSystems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        import ./pkgs { inherit pkgs; }
      );

      checks = forSupportedSystems (system: {
        formatting = treefmtEval.${system}.config.build.check self;
        pre-commit-check = gitHooksCheck.${system};
      });

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
