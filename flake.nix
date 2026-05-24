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
