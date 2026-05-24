{ pkgs, ... }:

let
  callPackage = pkgs.callPackage;
in
{
  brave-search-mcp-server = callPackage ./brave-search-mcp-server { };
  clash = callPackage ./clash { };
  clash-premium = callPackage ./clash-premium { };
  sing-box-alpha = callPackage ./sing-box-alpha { };
}
