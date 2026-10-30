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
  version = "0.1.2183";

  src = fetchFromGitHub {
    owner = "yetone";
    repo = "magpie";
    rev = "v${finalAttrs.version}";
    hash = "sha256-71IGaOCOLuwLQPAUbwWS4fZBwlbOxPRzVskOxZwXGnI=";
  };

  vendorHash = "sha256-CSFUYQB28DBs0oQSObJEqu07+b7T7DKxINQVu+lHNUw=";

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

  # Ignore auxiliary tags such as pf-v1; only vX.Y.Z tags identify Magpie versions.
  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version-regex"
      "^v([0-9]+[.][0-9]+[.][0-9]+)$"
    ];
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
