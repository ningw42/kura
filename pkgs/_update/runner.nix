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
    # The walk above records each package's attrPath as `kuraPackages.<name>`,
    # but our flake exposes packages at `flake.packages.${system}.<name>` —
    # so `nix-update --flake` (which reads attrPath from UPDATE_NIX_ATTR_PATH
    # and resolves `<flake>#<attrPath>`) can't find them and crashes inside
    # eval.nix's `unsafeGetAttrPos` on a null lookup.
    #
    # We can't make the two names match at the source:
    #
    #   - Exposing `flake.packages.${system}.kuraPackages` is rejected by
    #     `nix flake check` (everything under `packages.${system}` must be a
    #     derivation, not a nested attrset).
    #   - Exposing `flake.kuraPackages.${system}` at the flake root doesn't
    #     help either: nix-update's flake resolver only looks at
    #     `flake.packages.${system}.<path>` and `flake.<path>` — it has no
    #     fallback that threads `${system}` through a custom root attr.
    #   - Dropping the `kuraPackages` scoping attr and walking at the top
    #     level would mean walking all of nixpkgs to find our handful of
    #     packages, plus name collisions with upstream attrs (`skim`,
    #     `litellm`, ...).
    #
    # So the walker name (`kuraPackages.<name>`, fast/isolated walk) and the
    # flake-output name (`<name>`, what nix-update sees) are necessarily
    # different. We bridge them here by overriding `get-script` to stamp
    # `attrPath = pkg.pname` onto each updateScript — update.nix prefers
    # `updateScript.attrPath` over the walked path, so UPDATE_NIX_ATTR_PATH
    # ends up as `<name>` and nix-update resolves it against the flake.
    # (`pname` is the kura attr name in practice for every package here.)
    get-script =
      pkg:
      let
        script = pkg.updateScript or null;
      in
      if script == null then
        null
      else if builtins.isAttrs script then
        script // { attrPath = script.attrPath or pkg.pname; }
      else
        {
          command = script;
          attrPath = pkg.pname;
        };
  }
)
