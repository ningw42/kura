{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  zig_0_16,
  installAgentSkills,
  installShellFiles,
  libnotify,
  cctools,
  xcbuild,
  nix-update-script,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "herdr";
  version = "2026-09-29-9dc3a1df2b56";

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "herdrdev";
    repo = "herdr";
    rev = "preview-${finalAttrs.version}";
    hash = "sha256-dhAifTJeh8sfK0s/KzUZIo1qHlv+AFit3HOyCT+QC5E=";
  };

  cargoHash = "sha256-AqbC/E4Uoer/eMzqZFXoOomRvFfDMEfYJsZfSp4ozBE=";

  zigDeps = zig_0_16.fetchDeps {
    inherit (finalAttrs) pname version;
    src = "${finalAttrs.src}/vendor/libghostty-vt";
    fetchAll = true;
    hash = "sha256-Cy0DdSvce+fhOFIfxHMQGF2b2j16UkS27UpGbfC42XI=";
  };

  nativeBuildInputs = [
    zig_0_16
    installAgentSkills
    installShellFiles
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    cctools
    xcbuild
  ];

  env = {
    HERDR_BUILD_CHANNEL = "preview";
    HERDR_BUILD_ID = finalAttrs.version;
    HERDR_BUILD_COMMIT = lib.last (lib.splitString "-" finalAttrs.version);
    LIBGHOSTTY_VT_OPTIMIZE = "ReleaseFast";
    LIBGHOSTTY_VT_SIMD = "true";
    ZIG = lib.getExe zig_0_16;
  };

  postPatch = lib.optionalString stdenv.hostPlatform.isLinux ''
    # Rust supplies the compiler builtins. Bundling Zig's runtime leaves
    # overlapping unwind records that ld.bfd rejects (nixpkgs PR #568618).
    substituteInPlace vendor/libghostty-vt/src/build/GhosttyLibVt.zig \
      --replace-fail 'lib.bundle_compiler_rt = true;' 'lib.bundle_compiler_rt = false;' \
      --replace-fail 'lib.bundle_ubsan_rt = true;' 'lib.bundle_ubsan_rt = false;'

    substituteInPlace src/platform/linux.rs \
      --replace-fail 'let mut cmd = command("notify-send");' \
        'let mut cmd = command("${libnotify}/bin/notify-send");'
  '';

  # Upstream binary tests are renamed, added, or changed between releases and
  # depend on host process details, so Nix-only patches for them are brittle.
  doCheck = false;

  dontUseZigBuild = true;
  dontUseZigCheck = true;
  dontUseZigInstall = true;

  postConfigure = ''
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
    cp -rL ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
    chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  postInstall =
    lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      installShellCompletion --cmd herdr \
        --bash <("$out/bin/herdr" completion bash) \
        --fish <("$out/bin/herdr" completion fish) \
        --zsh <("$out/bin/herdr" completion zsh)
    ''
    + ''
      # Expose hook/plugin sources for declarative home-manager integration,
      # following llm-agents.nix without running `herdr integrate` at build time.
      install -d "$out/share/herdr"
      cp -r src/integration/assets "$out/share/herdr/integrations"
      find "$out/share/herdr/integrations" -name '*.test.ts' -delete
    '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    cargoVersion=$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
    test "$("$out/bin/herdr" --version)" = \
      "herdr $cargoVersion-preview.${finalAttrs.version}"

    # Ship every integration asset unchanged, except upstream test files.
    diff -r --exclude='*.test.ts' src/integration/assets "$out/share/herdr/integrations"
    test -z "$(find "$out/share/herdr/integrations" -name '*.test.ts' -print -quit)"

    runHook postInstallCheck
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
      "--version"
      "unstable"
      "--version-regex"
      "^preview-(.*)$"
      "--custom-dep"
      "zigDeps"
    ];
  };

  meta = {
    description = "Agent multiplexer that lives in your terminal (preview channel)";
    homepage = "https://herdr.dev";
    changelog = "https://github.com/herdrdev/herdr/releases/tag/preview-${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "herdr";
    platforms = lib.platforms.unix;
  };
})
