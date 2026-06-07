{ pkgs, ... }:

let
  callPackage = pkgs.callPackage;
  callPythonPackage = pkgs.python313Packages.callPackage;
in
{
  brave-search-mcp-server = callPackage ./brave-search-mcp-server { };
  byokey = callPackage ./byokey { };
  clash-premium = callPackage ./clash-premium { };
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
  router-maestro = callPackage ./router-maestro { };
  sing-box-alpha = callPackage ./sing-box-alpha { };
  skim = callPackage ./skim { };
  smartthings-soundbar = callPythonPackage ./smartthings-soundbar { };
  subsonic-now-playing-overlay = callPackage ./subsonic-now-playing-overlay { };
  telepush = callPackage ./telepush { };
  transmissionic = callPackage ./transmissionic { };
  trguing = callPackage ./trguing { };
  zashboard = callPackage ./zashboard { };
}
