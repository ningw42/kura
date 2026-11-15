{ nix-update, python3Packages }:

# TODO(removal): Remove once nix-update in both the pinned nixpkgs and
# shell.nix's pkgs includes the fix for https://github.com/Mic92/nix-update/issues/687.
# An upstream merge alone is not enough; both updater environments need the fix.
# Removal checklist:
# - Delete this file, ./nix-update-prefetch.patch, and ./test_nix_update.py.
# - In pkgs/default.nix, remove the nix-update binding and restore
#   callPackage = pkgs.callPackage; instead of the callPackageWith override.
# - In shell.nix, remove the nix-update let/in block and use pkgs.nix-update
#   in packages again.
# - KEEP flake.nix's context-preserving flakePath interpolation: that is a
#   permanent wrapper fix, independent of nix-update.
# Then run nix flake check --no-build and a real version/hash update.
#
# Nix >= 2.35 may report metadata paths without copying their source to the store.
nix-update.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./nix-update-prefetch.patch ];
  postCheck = (old.postCheck or "") + ''
    PYTHONPATH="$PWD" ${python3Packages.python.interpreter} ${./test_nix_update.py}
  '';
})
