{
  lib,
  buildGoModule,
  fetchFromGitHub,
  lazygit,
  testers,
  nix-update-script,
}:
buildGoModule (finalAttrs: {
  pname = "lazygit";
  version = "0.63.1";

  src = fetchFromGitHub {
    owner = "jesseduffield";
    repo = "lazygit";
    # Pin via `rev` (bare tag), not `tag`, so nix-update doesn't re-fetch the
    # dependency hashes on every no-op update. See AGENTS.md ("rev vs tag").
    rev = "v${finalAttrs.version}";
    hash = "sha256-vcpd04DEHmtEJtOOYohxHUgNtQfiChErWmNiQle8pvc=";
  };

  vendorHash = null;
  subPackages = [ "." ];

  ldflags = [
    "-X main.version=${finalAttrs.version}"
    "-X main.buildSource=nix"
  ];

  passthru = {
    tests.version = testers.testVersion { package = lazygit; };

    updateScript = nix-update-script {
      extraArgs = [
        "--flake"
        "--use-github-releases"
        "--version-regex"
        "^v([0-9.]+)$"
      ];
    };
  };

  meta = {
    description = "Simple terminal UI for git commands";
    homepage = "https://github.com/jesseduffield/lazygit";
    changelog = "https://github.com/jesseduffield/lazygit/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "lazygit";
  };
})
