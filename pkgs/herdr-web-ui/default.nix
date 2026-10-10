{
  lib,
  stdenv,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
  nodejs-slim_22,
  autoPatchelfHook,
  makeWrapper,
  writableTmpDirAsHomeHook,
  cacert,
  bash,
  coreutils,
  git,
  openssh,
  procps,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "herdr-web-ui";
  version = "0.4.5";

  src = fetchFromGitHub {
    owner = "devswha";
    repo = "herdr-web-ui";
    rev = "v${finalAttrs.version}";
    hash = "sha256-4hb3QR5h3PJseqGJYntSJAOVp1ToIXOLm7/I7nQJ4yE=";
  };

  nativeBuildInputs = [
    bun
    nodejs-slim_22
    autoPatchelfHook
    makeWrapper
    writableTmpDirAsHomeHook
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  strictDeps = true;

  configurePhase = ''
    runHook preConfigure

    cp -R ${finalAttrs.passthru.bunDeps}/node_modules .
    chmod -R u+w node_modules
    patchShebangs node_modules

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    # Vite compiles the Bun-patched xterm sources before bundling the client.
    bun --no-install run build

    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    bun --no-install run typecheck
    bun --no-install test server/auth.test.ts scripts/third-party-notices.test.ts
    test -s dist/THIRD_PARTY_NOTICES.md

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/herdr-web-ui"
    cp -R dist server shared package.json LICENSE THIRD_PARTY_NOTICES.md \
      "$out/lib/herdr-web-ui/"
    # The build tree carries devDependencies (Vite, TypeScript, Playwright); ship runtime ones only.
    cp -R ${finalAttrs.passthru.bunProdDeps}/node_modules "$out/lib/herdr-web-ui/"
    chmod -R u+w "$out/lib/herdr-web-ui/node_modules"
    patchShebangs "$out/lib/herdr-web-ui/node_modules"

    # The managed entrypoint rebuilds/self-updates. Run only the immutable server;
    # Herdr itself is supplied by the caller (HERDR_WEB_HERDR_BIN or PATH).
    # The PTY sidecar must use real Node, not Bun's Node compatibility shim.
    makeWrapper ${lib.getExe bun} "$out/bin/herdr-web-ui" \
      --chdir "$out/lib/herdr-web-ui" \
      --add-flags "--no-install run $out/lib/herdr-web-ui/server/index.ts" \
      --prefix PATH : ${
        lib.makeBinPath [
          bun
          nodejs-slim_22
          git
          openssh
          bash
          coreutils
          procps
        ]
      } \
      --set-default HERDR_WEB_TELEMETRY off

    runHook postInstall
  '';

  # Exercise the installed native addon after autoPatchelf, without a Herdr daemon.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ procps ];
  installCheckPhase = ''
    runHook preInstallCheck

    export HERDR_WEB_TELEMETRY=off HERDR_TEST_MODE=unit
    node "$out/lib/herdr-web-ui/server/pty/smoke.mjs"
    bun --no-install test "$out/lib/herdr-web-ui/server/pty/session.test.ts"

    runHook postInstallCheck
  '';

  passthru =
    let
      fetchBunDeps =
        {
          suffix,
          installFlags ? [ ],
          hash,
        }:
        stdenvNoCC.mkDerivation {
          pname = "${finalAttrs.pname}-${suffix}";
          inherit (finalAttrs) version src;
          nativeBuildInputs = [
            bun
            writableTmpDirAsHomeHook
          ];
          impureEnvVars = lib.fetchers.proxyImpureEnvVars;
          env.SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
          dontConfigure = true;
          buildPhase = ''
            runHook preBuild

            export BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
            # A hoisted tree avoids Bun's nondeterministic shared .bun symlink layout.
            bun install --frozen-lockfile --ignore-scripts --no-progress --linker hoisted \
              ${lib.escapeShellArgs installFlags}

            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall

            mkdir -p "$out"
            cp -R node_modules "$out/"
            rm -rf "$out/node_modules/.cache"

            runHook postInstall
          '';
          # No store references from rewritten shebangs or native library paths in a FOD.
          dontFixup = true;
          outputHash = hash;
          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
        };
    in
    {
      # Full tree for building and checking; the runtime tree omits devDependencies.
      bunDeps = fetchBunDeps {
        suffix = "bun-deps";
        hash = "sha256-44WPT3apQnLbPQogUALC/n2LmK3jKnatJXRoN99+lOo=";
      };
      bunProdDeps = fetchBunDeps {
        suffix = "bun-prod-deps";
        installFlags = [ "--production" ];
        hash = "sha256-0p1ggSSd5ROy3OytvjDhTvR0YlfebPhpuE9bdPNMLhU=";
      };
      updateScript = nix-update-script {
        extraArgs = [
          "--flake"
          "--use-github-releases"
          # The same repository also publishes unrelated remote-v* bridge bundles.
          "--version-regex"
          ''^v(\d+\.\d+\.\d+)$''
          "--custom-dep"
          "bunDeps"
          "--custom-dep"
          "bunProdDeps"
        ];
      };
    };

  meta = {
    description = "Browser UI for Herdr workspaces, terminals, and agents";
    homepage = "https://github.com/devswha/herdr-web-ui";
    changelog = "https://github.com/devswha/herdr-web-ui/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    mainProgram = "herdr-web-ui";
    platforms = [ "x86_64-linux" ];
  };
})
