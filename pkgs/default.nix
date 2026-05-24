{ pkgs, ... }:

let
  callPackage = pkgs.callPackage;
in
{
  brave-search-mcp-server = callPackage ./brave-search-mcp-server { };
}
