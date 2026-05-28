{
  stdenv,
  fetchzip,
  nix-update-script,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "trguing";
  version = "1.3.0";

  src = fetchzip {
    url = "https://github.com/openscopeproject/TrguiNG/releases/download/v${finalAttrs.version}/trguing-web-v${finalAttrs.version}.zip";
    hash = "sha256-nX+SNzfWG9lMRBMooX33kp2S8eOr6UKtiLSjJoLq/us=";
    stripRoot = false;
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share
    cp -r $src/* $out/share
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };
})
