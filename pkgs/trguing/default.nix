{
  stdenv,
  fetchzip,
}:

stdenv.mkDerivation {
  pname = "trguing";
  version = "1.3.0";

  src = fetchzip {
    url = "https://github.com/openscopeproject/TrguiNG/releases/download/v1.3.0/trguing-web-v1.3.0.zip";
    hash = "sha256-nX+SNzfWG9lMRBMooX33kp2S8eOr6UKtiLSjJoLq/us=";
    stripRoot = false;
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share
    cp -r $src/* $out/share
    runHook postInstall
  '';
}
