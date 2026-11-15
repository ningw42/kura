{ pkgs, ... }:

let
  # TODO(removal): Remove this wiring with ./_update/nix-update.nix; see its checklist.
  # Plain update scripts embed an absolute executable path, bypassing shell.nix.
  nix-update = pkgs.callPackage ./_update/nix-update.nix { };
  callPackage = pkgs.lib.callPackageWith (
    pkgs
    // {
      nix-update-script = pkgs.nix-update-script.override { inherit nix-update; };
    }
  );
  callPythonPackage = pkgs.python3Packages.callPackage;
in
{
  brave-search-mcp-server = callPackage ./brave-search-mcp-server { };
  clash-premium = callPackage ./clash-premium { };
  copilotd = callPackage ./copilotd { };
  fzf = callPackage ./fzf { };
  herdr = callPackage ./herdr { };
  koito = callPackage ./koito { };
  lazygit = callPackage ./lazygit { };
  magpie = callPackage ./magpie { };
  moor = callPackage ./moor { };
  moshi-hook = callPackage ./moshi-hook { };
  multi-scrobbler = callPackage ./multi-scrobbler { };
  ovis = callPackage ./ovis { };
  pi-coding-agent = callPackage ./pi-coding-agent { };
  pi-distribution = callPackage ./pi-distribution { };
  sing-box = callPackage ./sing-box { };
  skim = callPackage ./skim { };
  smartthings-soundbar = callPythonPackage ./smartthings-soundbar { };
  subsonic-now-playing-overlay = callPackage ./subsonic-now-playing-overlay { };
  telepush = callPackage ./telepush { };
  transmissionic = callPackage ./transmissionic { };
  trguing = callPackage ./trguing { };
  zashboard = callPackage ./zashboard { };
}
