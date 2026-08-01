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
  version = "3.16.1";

  src = fetchFromGitHub {
    owner = "Zephyruso";
    repo = "zashboard";
    # Pin via `rev` (bare tag), not `tag`, so nix-update doesn't re-fetch the
    # dependency hashes on every no-op update. See AGENTS.md ("rev vs tag").
    rev = "v${finalAttrs.version}";
    hash = "sha256-bG7Zk74C0/NOKR730wNZHkUpuIFTpUoe8MKE5eESYBE=";
  };

  npmDeps = null;
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-8EQziLcmP+bjQez+b0QdgF43XGydYC9yh4m9lEkbhCY=";
  };

  nativeBuildInputs = [ pnpm ];
  npmConfigHook = pnpmConfigHook;

  # Default `build` (vite build). As of v3.16.1 sing-box's native gRPC API
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
