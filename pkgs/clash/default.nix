{
  stdenv,
  fetchurl,
  autoPatchelfHook,
  gnutar,
  zstd,
}:

stdenv.mkDerivation {
  pname = "clash";
  version = "1.18.0";

  src = fetchurl {
    url = "https://mirrors.ustc.edu.cn/archlinux/extra/os/x86_64/clash-1.18.0-1-x86_64.pkg.tar.zst";
    hash = "sha256-GTWlFOSJooixUIUp/A20VZS2OXuRC/OYy9SsOhLUE58=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    gnutar
    zstd
  ];

  unpackPhase = ''
    tar --use-compress-program zstd -xvf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp usr/bin/clash $out/bin/clash

    runHook postInstall
  '';
}
