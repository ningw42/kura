{ pkgs, ... }:

let
  callPackage = pkgs.callPackage;
  callPythonPackage = pkgs.python313Packages.callPackage;
in
{
  brave-search-mcp-server = callPackage ./brave-search-mcp-server { };
  clash-premium = callPackage ./clash-premium { };
  copilot-proxy = callPackage ./copilot-proxy { };
  copilotd = callPackage ./copilotd { };
  fzf = callPackage ./fzf { };
  koito = callPackage ./koito { };
  lazygit = callPackage ./lazygit { };
  litellm =
    let
      py = pkgs.python313Packages;
      base = callPythonPackage ./litellm { };
    in
    py.toPythonApplication (
      base.overridePythonAttrs (old: {
        dependencies = (old.dependencies or [ ]) ++ base.optional-dependencies.proxy;
      })
    );
  moor = callPackage ./moor { };
  multi-scrobbler = callPackage ./multi-scrobbler { };
  pi-mcp-adapter = callPackage ./pi-mcp-adapter { };
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
