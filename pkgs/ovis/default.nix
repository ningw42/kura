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
  unixtools,
  writeShellScriptBin,
  nix-update-script,
}:

let
  ptyPlatforms = {
    aarch64-darwin = "darwin-arm64";
    x86_64-darwin = "darwin-x64";
    aarch64-linux = "linux-arm64";
    x86_64-linux = "linux-x64";
  };
  ptyPlatform =
    ptyPlatforms.${stdenv.hostPlatform.system}
      or (throw "Unsupported ovis platform: ${stdenv.hostPlatform.system}");
  ps = if stdenv.hostPlatform.isLinux then procps else unixtools.ps;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ovis";
  version = "0.4.16";

  src = fetchFromGitHub {
    owner = "devswha";
    repo = "ovis";
    rev = "v${finalAttrs.version}";
    hash = "sha256-kYZh9AOPYbmewwZeZkxuQ6w/mEbOQNI78bdHH7RPcws=";
  };

  nativeBuildInputs = [
    bun
    nodejs-slim_22
    makeWrapper
    writableTmpDirAsHomeHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
  ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
  ];
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
    # Invoke its JS entrypoint directly under Bun for the theme bootstrap plugin's
    # Bun.build, bypassing the package script and Vite's patched Node shebang.
    bun --no-install node_modules/vite/bin/vite.js build

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

    mkdir -p "$out/lib/ovis"
    cp -R dist server shared package.json LICENSE THIRD_PARTY_NOTICES.md \
      "$out/lib/ovis/"
    # The build tree carries devDependencies (Vite, TypeScript, Playwright); ship runtime ones only.
    cp -R ${finalAttrs.passthru.bunProdDeps}/node_modules "$out/lib/ovis/"
    chmod -R u+w "$out/lib/ovis/node_modules"
    # Keep only the host platform's prebuilt PTY addon so autoPatchelf and the
    # runtime closure do not carry foreign binaries.
    for pkg in "$out/lib/ovis/node_modules/@lydell"/node-pty-*; do
      if [ "$(basename "$pkg")" != "node-pty-${ptyPlatform}" ]; then
        rm -rf "$pkg"
      fi
    done
    patchShebangs "$out/lib/ovis/node_modules"

    # The managed entrypoint rebuilds/self-updates. Run only the immutable server;
    # Herdr itself is supplied by the caller (HERDR_WEB_HERDR_BIN or PATH).
    # The PTY sidecar must use real Node, not Bun's Node compatibility shim.
    makeWrapper ${lib.getExe bun} "$out/bin/ovis" \
      --chdir "$out/lib/ovis" \
      --add-flags "--no-install run $out/lib/ovis/server/index.ts" \
      --prefix PATH : ${
        lib.makeBinPath [
          bun
          nodejs-slim_22
          git
          openssh
          bash
          coreutils
          ps
        ]
      } \
      --set-default HERDR_WEB_TELEMETRY off

    runHook postInstall
  '';

  # Exercise the installed native addon after fixup, without a Herdr daemon.
  doInstallCheck = true;
  nativeInstallCheckInputs = [
    ps
  ]
  ++ lib.optionals (!stdenv.hostPlatform.isLinux) [
    (writeShellScriptBin "pgrep" ''
      ps -axww -o pid=,command= | SELF="$$" TAG="$2" awk '$1 != ENVIRON["SELF"] && index($0, ENVIRON["TAG"]) { print $1 }'
    '')
  ];
  installCheckPhase = ''
    runHook preInstallCheck

    export HERDR_WEB_TELEMETRY=off HERDR_TEST_MODE=unit
    node "$out/lib/ovis/server/pty/smoke.mjs"
    bun --no-install test "$out/lib/ovis/server/pty/session.test.ts"

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
            # Install optional packages for all supported OS/CPU targets so a single
            # FOD hash works on both Linux and Darwin.
            bun install --frozen-lockfile --ignore-scripts --no-progress \
              --linker hoisted --backend copyfile \
              --os=linux --os=darwin --cpu=x64 --cpu=arm64 \
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
        hash = "sha256-acMh6ru/BSyRwN6tXFvzhkna30d7uOTCL7/obYvvHPY=";
      };
      bunProdDeps = fetchBunDeps {
        suffix = "bun-prod-deps";
        installFlags = [ "--production" ];
        hash = "sha256-cppBgaAWxqb3ckzCcndPUCilo6G/E6PzUnLfy06265I=";
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
    homepage = "https://github.com/devswha/ovis";
    changelog = "https://github.com/devswha/ovis/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    mainProgram = "ovis";
    platforms = builtins.attrNames ptyPlatforms;
  };
})
