# Provides the runtime dependencies for `pkgs/_update/run.sh`.
#
# nixpkgs' maintainers/scripts/update.py wraps every updateScript invocation
# in `nix-shell ${nixpkgs_root}/shell.nix --run ...`, where nixpkgs_root is
# the git toplevel — i.e., this repo's root. So we need a shell.nix here that
# exposes the tools any of our updaters might invoke.
#
# Not used by humans — `nix develop` continues to drop you into the flake's
# proper devShell.
{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShellNoCC {
  packages = [
    pkgs.nix
    pkgs.nix-update
    pkgs.jq
    pkgs.curl
    pkgs.git
    pkgs.gnused
    pkgs.gnugrep
    pkgs.gawk
    pkgs.prefetch-npm-deps
    pkgs.nodejs_22
    pkgs.yarn-berry_4-fetcher.yarn-berry-fetcher
  ];
}
