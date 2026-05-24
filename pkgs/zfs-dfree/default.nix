{
  writeShellApplication,
  coreutils,
  gawk,
  zfs,
}:

writeShellApplication {
  name = "dfree";

  runtimeInputs = [
    coreutils
    gawk
    zfs
  ];

  text = builtins.readFile ./dfree.sh;
}
