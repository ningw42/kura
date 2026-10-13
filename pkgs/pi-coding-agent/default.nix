{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  nix-update-script,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  ripgrep,
  fd,
  libxcb,
  makeBinaryWrapper,
  patchelf,
  stdenvNoCC,
}:
buildNpmPackage (finalAttrs: {
  pname = "pi-coding-agent";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    rev = "v${finalAttrs.version}";
    hash = "sha256-IjNJvVxjzRur2foQDWPA5iM9sa3ThBoZU1/LT5pU6jc=";
  };

  npmDepsHash = "sha256-P/KWhkvLjtpWRiwLCHu2iUVyI8nragSnQGWUQNsRhw8=";

  # The generated provider model catalog is gitignored upstream. Restore it
  # from the matching pi-ai npm release so the source build stays offline.
  # The updater refreshes this hash alongside the source and dependency hashes.
  modelData = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${finalAttrs.version}.tgz";
    hash = "sha256-w+aUI7yrlxLzGn5bbTRIrjVq+EQ57GvHAfYm9uoWRTU=";
  };

  preConfigure = ''
    mkdir -p packages/ai/src/providers/data
    tar --extract --gzip --file=${finalAttrs.modelData} \
      --directory=packages/ai/src/providers/data \
      --strip-components=4 \
      package/dist/providers/data
  '';

  npmWorkspace = "packages/coding-agent";

  # Skip native module rebuilds for unneeded workspaces, such as web-ui canvas.
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    makeBinaryWrapper
  ]
  ++ lib.optional stdenvNoCC.hostPlatform.isLinux patchelf;

  buildPhase = ''
    runHook preBuild

    npm run build:offline

    runHook postBuild
  '';

  dontNpmPrune = true;

  preInstall = ''
    npm prune --omit=dev --no-save
  '';

  # The npm workspace symlinks otherwise point into a missing packages/ tree.
  postInstall = ''
    local nm="$out/lib/node_modules/pi-monorepo/node_modules"

    # Follow runtime dependencies instead of hardcoding workspace names, which
    # upstream can remove or rename between releases.
    node --input-type=module - "$nm" <<'JS'
    import fs from "node:fs";
    import path from "node:path";

    const workspaces = new Map();
    for (const entry of fs.readdirSync("packages")) {
      const directory = path.join("packages", entry);
      const manifest = path.join(directory, "package.json");
      if (!fs.existsSync(manifest)) continue;
      const pkg = JSON.parse(fs.readFileSync(manifest, "utf8"));
      workspaces.set(pkg.name, { directory, pkg });
    }

    const root = JSON.parse(fs.readFileSync("packages/coding-agent/package.json", "utf8")).name;
    const pending = [root];
    const seen = new Set();
    while (pending.length) {
      const name = pending.pop();
      if (seen.has(name) || !workspaces.has(name)) continue;
      seen.add(name);
      const { directory, pkg } = workspaces.get(name);
      pending.push(...Object.keys({
        ...pkg.dependencies,
        ...pkg.optionalDependencies,
        ...pkg.peerDependencies,
      }));
      if (name === root) continue;
      const destination = path.join(process.argv[2], name);
      fs.rmSync(destination, { recursive: true, force: true });
      fs.cpSync(directory, destination, { recursive: true });
    }
    JS

    find "$nm" -type l -lname '*/packages/*' -delete
    find "$nm/.bin" -xtype l -delete
  ''
  + lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
    # The prebuilt TUI helper links to libxcb, which is not on Nix's loader path.
    for addon in "$nm/@earendil-works/pi-tui/native/linux/prebuilds/"*/linux-platform-x11.node; do
      patchelf --add-rpath ${lib.makeLibraryPath [ libxcb ]} "$addon"
    done
  ''
  + lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
    # Foreign Linux binaries would make audit-tmpdir inspect ELF RPATHs.
    rm -rf \
      "$nm/@anthropic-ai/sandbox-runtime/dist/vendor/seccomp" \
      "$nm/@anthropic-ai/sandbox-runtime/vendor/seccomp"
  '';

  postFixup = ''
    wrapProgram $out/bin/pi --prefix PATH : ${
      lib.makeBinPath [
        ripgrep
        fd
      ]
    } \
      --set-default PI_SKIP_VERSION_CHECK 1 \
      --set-default PI_TELEMETRY 0
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    writableTmpDirAsHomeHook
    versionCheckHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];
  versionCheckProgram = "${placeholder "out"}/bin/pi";
  versionCheckProgramArg = "--version";

  # Exercise the installed dependency graph and restored model catalog without
  # credentials or network access, rather than checking only the CLI version.
  postInstallCheck = ''
    node --input-type=module - "$out/lib/node_modules/pi-monorepo" <<'JS'
    import { createRequire } from "node:module";
    import path from "node:path";

    const pkgdir = process.argv[2];
    await import(path.join(pkgdir, "dist/index.js"));
    const platform = process.platform;
    const nativeFile = platform + "-platform" + (platform === "linux" ? "-x11" : "") + ".node";
    createRequire(import.meta.url)(path.join(
      pkgdir, "node_modules/@earendil-works/pi-tui/native", platform,
      "prebuilds", platform + "-" + process.arch, nativeFile,
    ));
    JS
    "$out/bin/pi" --list-models > "$TMPDIR/pi-models.txt"
    test -s "$TMPDIR/pi-models.txt"
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
      "--custom-dep"
      "modelData"
    ];
  };

  meta = {
    description = "Coding agent CLI with read, bash, edit, write tools and session management";
    homepage = "https://pi.dev/";
    downloadPage = "https://www.npmjs.com/package/@earendil-works/pi-coding-agent";
    changelog = "https://github.com/earendil-works/pi/blob/v${finalAttrs.version}/packages/coding-agent/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
})
