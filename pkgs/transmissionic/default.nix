{
  stdenv,
  fetchzip,
}:

stdenv.mkDerivation {
  pname = "transmissionic";
  version = "1.7.1";

  src = fetchzip {
    url = "https://github.com/6c65726f79/Transmissionic/releases/download/v1.7.1/Transmissionic-webui-v1.7.1.zip";
    hash = "sha256-svwfbJccvs9bZdiJGsC6vq43YGHiiePEwX6QX96mmTc=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share
    cp -r $src/* $out/share
    runHook postInstall
  '';
}
