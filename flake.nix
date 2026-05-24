{
  description = "Ning's personal Nix package collection (kura, 蔵). Cached via Garnix.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forSupportedSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = forSupportedSystems (
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        }
      );
    in
    {
      # Overlay consumers add to their own pkgs to get every kura package
      # exposed as a top-level attribute (e.g. pkgs.brave-search-mcp-server).
      overlays.default = final: prev: import ./pkgs { pkgs = prev; };

      # Pre-built packages, indexed by system. Garnix builds these on every
      # push and uploads to cache.garnix.io, so consumers never recompile.
      packages = forSupportedSystems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        import ./pkgs { inherit pkgs; }
      );

      formatter = forSupportedSystems (system: pkgsFor.${system}.nixfmt-rfc-style);
    };
}
