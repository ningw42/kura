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
  version = "3.10.1";

  src = fetchFromGitHub {
    owner = "Zephyruso";
    repo = "zashboard";
    # Pin via `rev` (bare tag), not `tag`, so nix-update doesn't re-fetch the
    # dependency hashes on every no-op update. See AGENTS.md ("rev vs tag").
    rev = "v${finalAttrs.version}";
    hash = "sha256-unk/QO2V5BzuY8TL8Z1K/EPPMB6JwW15OQICix8Mukk=";
  };

  npmDeps = null;
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-7bjsqBQssirsrIbegm5G/J/v3+yzfomq/gxCbxKEb6g=";
  };

  nativeBuildInputs = [ pnpm ];
  npmConfigHook = pnpmConfigHook;

  # Build the sing-box-native variant (upstream's `build:singbox` script sets
  # SINGBOX_NATIVE=true), which bundles the ConnectRPC/protobuf client, xterm,
  # and qrcode tooling so the dashboard can drive sing-box's native API. The
  # extra deps already live in the pnpm lockfile, so pnpmDeps is unaffected.
  npmBuildScript = "build:singbox";

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
