{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  nix-update-script,
}:
let
  pnpm = pnpm_10;
in
buildNpmPackage (finalAttrs: {
  pname = "zashboard";
  version = "3.22.0";

  src = fetchFromGitHub {
    owner = "Zephyruso";
    repo = "zashboard";
    # Pin via `rev` (bare tag), not `tag`, so nix-update doesn't re-fetch the
    # dependency hashes on every no-op update. See AGENTS.md ("rev vs tag").
    rev = "v${finalAttrs.version}";
    hash = "sha256-K7WZnFXgiSI/pxhDWfoWX9tHKJiNK1wbO6qowUu1hOo=";
  };

  npmDeps = null;
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-jbTAN9QbhXiGzD/McdoN62JIdRL8MA/v/kdLawWbokU=";
  };

  nativeBuildInputs = [ pnpm ];
  npmConfigHook = pnpmConfigHook;

  # Default `build` (vite build). As of v3.22.0 sing-box's native gRPC API
  # support is always bundled (lazily loaded so the Clash backend doesn't pay
  # for it) — the dedicated `build:singbox` script was removed when upstream
  # folded the variant into the default build.
  npmBuildScript = "build";

  postPatch = ''
    substituteInPlace vite.config.ts \
      --replace-fail "getGitCommitId()" '""'
  '';

  __darwinAllowLocalNetworking = true;

  installPhase = ''
    runHook preInstall

    cp -r dist $out

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };

  meta = {
    description = "Dashboard Using Clash API";
    homepage = "https://github.com/Zephyruso/zashboard";
    changelog = "https://github.com/Zephyruso/zashboard/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
  };
})
