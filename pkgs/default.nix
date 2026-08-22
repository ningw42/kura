{ pkgs, ... }:

let
  callPackage = pkgs.callPackage;
  callPythonPackage = pkgs.python3Packages.callPackage;
in
{
  brave-search-mcp-server = callPackage ./brave-search-mcp-server { };
  clash-premium = callPackage ./clash-premium { };
  copilotd = callPackage ./copilotd { };
  fzf = callPackage ./fzf { };
  koito = callPackage ./koito { };
  lazygit = callPackage ./lazygit { };
  litellm =
    let
      py = pkgs.python3Packages;
      base = callPythonPackage ./litellm { };
    in
    py.toPythonApplication (
      base.overridePythonAttrs (old: {
        dependencies = (old.dependencies or [ ]) ++ base.optional-dependencies.proxy;
      })
    );
  moor = callPackage ./moor { };
  multi-scrobbler = callPackage ./multi-scrobbler { };
  paseo = callPackage ./paseo { };
  pi-distribution = callPackage ./pi-distribution { };
  router-maestro = callPackage ./router-maestro { };
  sing-box = callPackage ./sing-box { };
  skim = callPackage ./skim { };
  smartthings-soundbar = callPythonPackage ./smartthings-soundbar { };
  subsonic-now-playing-overlay = callPackage ./subsonic-now-playing-overlay { };
  telepush = callPackage ./telepush { };
  transmissionic = callPackage ./transmissionic { };
  trguing = callPackage ./trguing { };
  zashboard = callPackage ./zashboard { };
}
