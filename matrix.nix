# Expand the CI build list into a GitHub Actions matrix.
#
# Called from .github/workflows/build-and-push-to-caches.yml. Wildcards
# (`packages.<system>.*`) are expanded by reading attribute names from the
# flake; specific entries are passed through. Unknown systems throw rather
# than silently dropping rows, so a typo fails CI instead of skipping a
# package.
#
# `includes` below is a hand-maintained duplicate of `builds.include` in
# `garnix.yaml`. Garnix is on a deprecation path; once it's gone, garnix.yaml
# leaves the repo and this file becomes the sole source of truth. Until then,
# edit both when adding a package to the cache pipeline.
{
  self,
}:
let
  lib = self.inputs.nixpkgs.lib;

  # Mirror of garnix.yaml's builds.include. Keep in sync.
  includes = [
    "packages.x86_64-linux.*"
    "packages.aarch64-darwin.fzf"
    "packages.aarch64-darwin.lazygit"
    "packages.aarch64-darwin.skim"
  ];

  # Each supported system maps to the GitHub-hosted runner image used to
  # build it. Add a row here when opting a new platform into the cache
  # pipeline.
  systemRunners = {
    "x86_64-linux" = "ubuntu-latest";
    "aarch64-darwin" = "macos-latest";
  };

  parseEntry =
    entry:
    let
      parts = lib.splitString "." entry;
      prefix = builtins.elemAt parts 0;
      system = builtins.elemAt parts 1;
      package = lib.concatStringsSep "." (lib.drop 2 parts);
      runner =
        systemRunners.${system}
          or (throw "matrix.nix: unsupported system '${system}' in include '${entry}'");
      mkRow = name: {
        inherit system runner;
        package = name;
      };
    in
    if prefix != "packages" || builtins.length parts < 3 then
      throw "matrix.nix: unsupported include '${entry}' (expected packages.<system>.<name>)"
    else if package == "*" then
      map mkRow (builtins.attrNames self.packages.${system})
    else
      [ (mkRow package) ];
in
builtins.concatMap parseEntry includes
