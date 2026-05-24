{ pkgs, ... }:

let
  callPackage = pkgs.callPackage;
in
{
  brave-search-mcp-server = callPackage ./brave-search-mcp-server { };
  clash = callPackage ./clash { };
  sing-box-alpha = callPackage ./sing-box-alpha { };
}
