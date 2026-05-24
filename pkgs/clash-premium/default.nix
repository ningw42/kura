{
  stdenv,
  fetchurl,
  autoPatchelfHook,
  gzip,
}:

stdenv.mkDerivation {
  pname = "clash-premium";
  version = "2023.08.17";

  src = fetchurl {
    url = "https://github.com/Loyalsoldier/clash-rules/raw/hidden/software/clash-premium/clash-linux-amd64-v3-2023.08.17.gz";
    hash = "sha256-n/2jOQ08rdhEdLpPm/vHn8sMZTNPsX4j/88tiTHSbh4=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    gzip
  ];

  unpackPhase = ''
    gunzip -c $src > clash-premium
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    chmod +x clash-premium
    cp clash-premium $out/bin/clash

    runHook postInstall
  '';
}
