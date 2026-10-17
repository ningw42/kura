{
  lib,
  buildGoModule,
  fetchFromGitHub,
  bun,
  makeWrapper,
  nix-update-script,
  versionCheckHook,
}:

buildGoModule (finalAttrs: {
  pname = "magpie";
  version = "0.1.1279";

  src = fetchFromGitHub {
    owner = "yetone";
    repo = "magpie";
    rev = "v${finalAttrs.version}";
    hash = "sha256-2S2yaJb0Ba6peANidB2GEwGsjxOS751aVYpA1HzF0N8=";
  };

  vendorHash = "sha256-pBk3sQZ9/1sVdz2ZteBGgQrI49fDfgsQ8ur7pzM477A=";

  subPackages = [ "." ];
  tags = [ "nogui" ];
  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X=main.version=v${finalAttrs.version}"
  ];

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ bun ];
  preCheck = ''
    export MAGPIE_BUN="${lib.getExe bun}"
  '';

  # Use Nix's Bun rather than downloading an upstream binary at runtime for plugins.
  postInstall = ''
    wrapProgram "$out/bin/magpie" \
      --set-default MAGPIE_BUN "${lib.getExe bun}"
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "version";

  # Source tags live here; GitHub releases live in yetone/magpie-releases.
  passthru.updateScript = nix-update-script {
    extraArgs = [ "--flake" ];
  };

  meta = {
    description = "Headless AI-agent configuration manager and model API gateway";
    homepage = "https://github.com/yetone/magpie";
    changelog = "https://github.com/yetone/magpie-releases/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "magpie";
    platforms = lib.platforms.unix;
  };
})
