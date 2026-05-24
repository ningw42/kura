{ ... }:
{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;

  programs.yamlfmt.enable = true;
  programs.yamlfmt.includes = [
    "*.yaml"
    "*.yml"
  ];
  programs.yamlfmt.excludes = [
    ".pre-commit-config.yaml"
  ];
}
