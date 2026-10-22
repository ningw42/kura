{
  lib,
  autoPatchelfHook,
  buildNpmPackage,
  bun,
  fetchurl,
  fd,
  libxcb,
  nix-update-script,
  patchelf,
  rcodesign,
  ripgrep,
  stdenv,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  useBun ? true,
}:

let
  nativeTargets = {
    aarch64-darwin = "darwin-arm64";
    aarch64-linux = "linux-arm64";
    x86_64-linux = "linux-x64";
  };
  nativeTarget =
    nativeTargets.${stdenv.hostPlatform.system}
      or (throw "Unsupported Pi platform: ${stdenv.hostPlatform.system}");
  nativePlatform = if stdenv.hostPlatform.isDarwin then "darwin" else "linux";
  nativeFile = "${nativePlatform}-platform${lib.optionalString stdenv.hostPlatform.isLinux "-x11"}.node";
in
buildNpmPackage (finalAttrs: {
  pname = "pi-coding-agent";
  version = "1.4.0";

  # Follow llm-agents.nix: compile the already-built npm release with Bun.
  # Keep the registry fetch visible to nix-update for version/hash discovery.
  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${finalAttrs.version}.tgz";
    hash = "sha256-0VXBbvb6AJYPv1iykRU26AsF8zcA4LFPvQiWft4MdCg=";
  };

  postPatch = ''
    rm -f npm-shrinkwrap.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-yYhDc2lnoH+UvZT+d4uFIhD4/5SP2v/xaFosfig3yPQ=";
  makeCacheWritable = true;

  # The npm tarball already contains the compiled JavaScript and model catalog.
  dontNpmBuild = true;

  nativeBuildInputs =
    lib.optional useBun bun
    ++ lib.optional (useBun && stdenv.hostPlatform.isLinux) autoPatchelfHook
    ++ lib.optional (useBun && stdenv.hostPlatform.isDarwin) rcodesign
    ++ lib.optional (!useBun && stdenv.hostPlatform.isLinux) patchelf;

  buildInputs = lib.optional stdenv.hostPlatform.isLinux libxcb;

  # A compiled binary preserves extension module aliasing; running the Bun
  # entrypoint as a script does not. Node remains an optional fallback.
  preInstall = lib.optionalString useBun ''
    # The npm release only has dist/, but embedded worker paths use src/.
    mkdir -p src/utils src/modes src/core src/extensions/codemode
    echo 'import "../../dist/utils/image-resize-worker.js";' > src/utils/image-resize-worker.ts
    echo 'import "../../../dist/extensions/codemode/worker.js";' > src/extensions/codemode/worker.ts
    ln -s ../../dist/modes/interactive src/modes/interactive
    ln -s ../../dist/core/export-html src/core/export-html

    # package.json autoload fixes extension main/exports resolution. Do not
    # autoload project bunfig.toml or .env files, matching upstream's isolation.
    bun build --compile \
      --no-compile-autoload-bunfig \
      --no-compile-autoload-dotenv \
      --compile-autoload-package-json \
      ./dist/bun/cli.js \
      ./src/utils/image-resize-worker.ts \
      ./src/extensions/codemode/worker.ts \
      --outfile dist/pi
  '';

  postInstall =
    if useBun then
      ''
        pkgdir=$out/libexec/pi

        # Replace the npm installation with the standalone release layout.
        rm -rf "$out/lib" "$out/bin"
        mkdir -p "$out/bin" "$pkgdir/theme" "$pkgdir/assets"
        cp dist/pi "$pkgdir/"
        cp package.json README.md CHANGELOG.md "$pkgdir/"
        mkdir -p "$pkgdir/native/${nativePlatform}/prebuilds"
        cp -r node_modules/@earendil-works/pi-tui/native/${nativePlatform}/prebuilds/${nativeTarget} \
          "$pkgdir/native/${nativePlatform}/prebuilds/"
        cp node_modules/@silvia-odwyer/photon-node/photon_rs_bg.wasm "$pkgdir/"
        cp dist/modes/interactive/theme/*.json "$pkgdir/theme/"
        cp dist/modes/interactive/assets/* "$pkgdir/assets/"
        cp -r dist/core/export-html "$pkgdir/"
        cp -r docs examples "$pkgdir/"
        # Shipped examples must not pull Node into the closure via shebangs.
        find "$pkgdir" -name '*.js' -exec chmod -x {} +

        makeWrapper "$pkgdir/pi" "$out/bin/pi" \
          --prefix PATH : ${
            lib.makeBinPath [
              fd
              ripgrep
            ]
          } \
          --set PI_PACKAGE_DIR "$pkgdir" \
          --set PI_SKIP_VERSION_CHECK 1 \
          --set PI_TELEMETRY 0
      ''
    else
      lib.optionalString stdenv.hostPlatform.isLinux ''
        # Node mode has no autoPatchelf hook, but its native TUI helper needs libxcb.
        for addon in "$out/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui/native/linux/prebuilds/"*/linux-platform-x11.node; do
          patchelf --add-rpath ${lib.makeLibraryPath [ libxcb ]} "$addon"
        done
      ''
      + ''
        wrapProgram "$out/bin/pi" \
          --prefix PATH : ${
            lib.makeBinPath [
              fd
              ripgrep
            ]
          } \
          --set PI_SKIP_VERSION_CHECK 1 \
          --set PI_TELEMETRY 0
      '';

  # Darwin fixup can invalidate Bun's embedded signature; sign afterward.
  postFixup = lib.optionalString (useBun && stdenv.hostPlatform.isDarwin) ''
    ${lib.getExe rcodesign} sign --code-signature-flags linker-signed $out/libexec/pi/pi
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];
  versionCheckProgram = "${placeholder "out"}/bin/pi";
  versionCheckProgramArg = "--version";

  postInstallCheck =
    (
      if useBun then
        ''
          ${bun}/bin/bun --eval 'require(process.argv[1])' \
            "$out/libexec/pi/native/${nativePlatform}/prebuilds/${nativeTarget}/${nativeFile}"
        ''
      else
        lib.optionalString (builtins.hasAttr stdenv.hostPlatform.system nativeTargets) ''
          node -e 'require(process.argv[1])' \
            "$out/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui/native/${nativePlatform}/prebuilds/${nativeTarget}/${nativeFile}"
        ''
    )
    + ''
      "$out/bin/pi" --list-models > "$TMPDIR/pi-models.txt"
      test -s "$TMPDIR/pi-models.txt"
    '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--generate-lockfile"
    ];
  };

  meta = {
    description = "A terminal-based coding agent with multi-model support";
    homepage = "https://pi.dev/";
    downloadPage = "https://www.npmjs.com/package/@earendil-works/pi-coding-agent";
    changelog = "https://github.com/earendil-works/pi/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    platforms = if useBun then builtins.attrNames nativeTargets else lib.platforms.all;
    mainProgram = "pi";
  };
})
