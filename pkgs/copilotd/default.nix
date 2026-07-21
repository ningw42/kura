{
  buildGo126Module,
  fetchFromGitHub,
  versionCheckHook,
}:

buildGo126Module (finalAttrs: {
  pname = "copilotd";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "ningw42";
    repo = "copilotd";
    rev = "v${finalAttrs.version}";
    hash = "sha256-wKto6P3OWEgd619kYkep/vWiq1BKArfSLmokzUd5QxA=";
  };

  vendorHash = "sha256-73yGo/EY0X8gyiA8okgXM79ky2OF6T08+LzTStEMECg=";

  subPackages = [ "cmd/copilotd" ];

  ldflags = [
    "-s"
    "-w"
    "-X=github.com/ningw42/copilotd/internal/build.Version=v${finalAttrs.version}"
  ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "version";

  passthru.updateScript = [
    ../_update/run.sh
    "--attr"
    "copilotd"
    "--use-github-releases"
    "--post-hook"
    "sync-go-builder:ningw42/copilotd:v"
  ];

  meta = {
    description = "Run Anthropic Messages and OpenAI Responses APIs using GitHub Copilot";
    homepage = "https://github.com/ningw42/copilotd";
    changelog = "https://github.com/ningw42/copilotd/releases/tag/v${finalAttrs.version}";
    mainProgram = "copilotd";
  };
})
