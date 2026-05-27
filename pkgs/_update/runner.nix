# Wrapper around nixpkgs' maintainers/scripts/update.nix so it works against
# this flake's packages instead of nixpkgs' own attrs.
#
# Normally invoked via `nix run .#update [-- <args>]`. flake.nix interpolates
# the flake path so we can `getFlake` it back at evaluation time (under
# --impure; update is inherently impure anyway since it hits the network).
{
  flakePath,
  system,
  path ? "",
  ...
}@args:
let
  flake = builtins.getFlake (toString flakePath);
  nixpkgs = flake.inputs.nixpkgs;
in
import (nixpkgs + "/maintainers/scripts/update.nix") (
  (removeAttrs args [
    "flakePath"
    "system"
    "path"
  ])
  // {
    include-overlays = [
      (final: prev: { kuraPackages = flake.packages.${system}; })
    ];
    # Scope the runner to `kuraPackages.*` so it doesn't try to walk nixpkgs.
    path = if path == "" || path == null then "kuraPackages" else "kuraPackages.${path}";
  }
)
