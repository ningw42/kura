# Expand the CI build list into a GitHub Actions matrix.
#
# Called by the validation and cache-publishing workflows. Wildcards
# (`packages.<system>.*`) are expanded by reading attribute names from the
# flake; specific entries are passed through. When `previous` is provided,
# only new targets and targets whose Nix output path changed are returned.
# Unknown systems throw rather than silently dropping rows, so a typo fails
# CI instead of skipping a package.
#
# `includes` below is the build list — the sole source of truth for what CI
# validates and the cache pipeline publishes per platform. Add a package's
# attr path here to opt it into both.
{
  self,
  previous ? null,
}:
let
  lib = self.inputs.nixpkgs.lib;

  # The build list. Each entry is a `packages.<system>.<name>` attr path;
  # `<name>` may be `*` to build every package for that system.
  includes = [
    "packages.x86_64-linux.*"
    "packages.aarch64-darwin.fzf"
    "packages.aarch64-darwin.lazygit"
    "packages.aarch64-darwin.moor"
    "packages.aarch64-darwin.pi-distribution"
    "packages.aarch64-darwin.skim"
  ];

  # Each supported system maps to the GitHub-hosted runner image used to
  # build it. Add a row here when opting a new platform into CI.
  systemRunners = {
    "x86_64-linux" = "ubuntu-latest";
    "aarch64-darwin" = "macos-latest";
  };

  parseEntry =
    flake: entry:
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
      map mkRow (builtins.attrNames flake.packages.${system})
    else
      [ (mkRow package) ];

  rows = builtins.concatMap (parseEntry self) includes;
  rowKey = row: "${row.system}.${row.package}";

  # Matrix membership matters independently of derivation identity: opting an
  # existing package into a new platform must build it even if that derivation
  # already existed in the previous flake.
  previousRows =
    if previous == null then
      [ ]
    else
      let
        previousMatrix = previous.outPath + "/matrix.nix";
      in
      if builtins.pathExists previousMatrix then import previousMatrix { self = previous; } else [ ];
  previousRowKeys = map rowKey previousRows;

  packageAt =
    flake: row:
    lib.attrByPath (
      [
        "packages"
        row.system
      ]
      ++ lib.splitString "." row.package
    ) null flake;

  currentOutPath =
    row:
    let
      package = packageAt self row;
    in
    if package == null || !(builtins.isAttrs package && package ? outPath) then
      throw "matrix.nix: '${rowKey row}' is not a package derivation"
    else
      toString package.outPath;

  previousOutPath =
    row:
    let
      package = packageAt previous row;
    in
    if package == null || !(builtins.isAttrs package && package ? outPath) then
      null
    else
      toString package.outPath;

  changedSincePrevious =
    row:
    previous == null
    || !(builtins.elem (rowKey row) previousRowKeys)
    || previousOutPath row != currentOutPath row;
in
builtins.filter changedSincePrevious rows
