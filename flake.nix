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
      # Plain nixpkgs per system; kura packages currently only depend on
      # nixpkgs, so we don't apply self.overlays.default here. If a future
      # kura package needs to consume another kura package, switch the
      # overlay to use `final` (instead of `prev`) and re-apply it.
      pkgsFor = forSupportedSystems (system: import nixpkgs { inherit system; });
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

      formatter = forSupportedSystems (system: pkgsFor.${system}.nixfmt-rfc-style);
    };
}
