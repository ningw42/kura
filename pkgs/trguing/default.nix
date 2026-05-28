{
  stdenv,
  fetchzip,
  nix-update-script,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "trguing";
  version = "1.5.1";

  src = fetchzip {
    url = "https://github.com/openscopeproject/TrguiNG/releases/download/v${finalAttrs.version}/trguing-web-v${finalAttrs.version}.zip";
    hash = "sha256-yiJN21fz3sgtm5YSkvR9DMGT3LuKXO5cLF/ELcN8a/4=";
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
