{
  buildGo127Module,
  fetchFromGitHub,
  versionCheckHook,
}:

buildGo127Module (finalAttrs: {
  pname = "copilotd";
  version = "0.7.3";

  src = fetchFromGitHub {
    owner = "ningw42";
    repo = "copilotd";
    rev = "v${finalAttrs.version}";
    hash = "sha256-PdQh9GTrAXhDhLi+LtHmnAQlYfPvSZsvpMgS9y1Fek0=";
  };

  vendorHash = "sha256-hf+aCbbDjGOHABCEvj2F7MbsZullpbdSqmkedd7sfIA=";

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
    "--pre-hook"
    "sync-go-builder:ningw42/copilotd:v"
  ];

  meta = {
    description = "Run Anthropic Messages and OpenAI Responses APIs using GitHub Copilot";
    homepage = "https://github.com/ningw42/copilotd";
    changelog = "https://github.com/ningw42/copilotd/releases/tag/v${finalAttrs.version}";
    mainProgram = "copilotd";
  };
})
