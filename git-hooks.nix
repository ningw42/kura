{ treefmtWrapper, ... }:
{
  treefmt = {
    enable = true;
    packageOverrides.treefmt = treefmtWrapper;
  };
  check-added-large-files = {
    enable = true;
    args = [ "--maxkb=2048" ];
  };
  check-merge-conflicts.enable = true;
  detect-private-keys.enable = true;
  end-of-file-fixer.enable = true;
  mixed-line-endings = {
    enable = true;
    args = [ "--fix=lf" ];
  };
  trim-trailing-whitespace.enable = true;
  convco.enable = true;
}
