{ pkgs, ... }:

let
  callPackage = pkgs.callPackage;
in
{
  brave-search-mcp-server = callPackage ./brave-search-mcp-server { };
  sing-box-alpha = callPackage ./sing-box-alpha { };
}
