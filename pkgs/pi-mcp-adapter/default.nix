{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  makeWrapper,
}:

buildNpmPackage rec {
  pname = "pi-mcp-adapter";
  version = "2.11.0";

  src = fetchFromGitHub {
    owner = "nicobailon";
    repo = "pi-mcp-adapter";
    rev = "v${version}";
    hash = "sha256-JjYS9tPSoVuubdmHTqTNNYfDJOc9CBPvVbIxvdJWi7M=";
  };

  # Upstream ships no lockfile, so we vendor a production-only one regenerated
  # with npm 10 (so transitive deps carry `resolved`/`integrity`). devDependencies
  # are dropped on purpose: there's no build or test step here, the dev toolchain
  # (vite/vitest/tsx/@earendil-works/pi-coding-agent) would only bloat the FOD,
  # and three of its transitive entries lack integrity, which breaks fetchNpmDeps.
  # See pkgs/_update/hooks.sh (regen-npm-lockfile with the `omit-dev` flag) for
  # the matching update path.
  #
  # The strip of devDependencies keeps package.json in sync with the production-
  # only lockfile so `npm ci` (in npmConfigHook, which runs before preConfigure)
  # validates. It's guarded on `node` so it no-ops inside the fetchNpmDeps FOD,
  # whose minimal stdenv has no node and which only reads the lockfile anyway.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    if command -v node >/dev/null; then
      node --eval 'const fs = require("fs"); const p = JSON.parse(fs.readFileSync("package.json")); delete p.devDependencies; fs.writeFileSync("package.json", JSON.stringify(p, null, 2));'
    fi
  '';

  npmDepsHash = "sha256-Mn2ug9W940FgluNyajkF130W3pWrbmKnyLkH7ND8jwU=";

  # The package has no build step: it ships its TypeScript sources directly and
  # Pi loads them at runtime. Only cli.js (the `pi-mcp-adapter init` helper) is
  # plain JS.
  dontNpmBuild = true;

  # Dependency install scripts aren't needed — recheck's per-platform native
  # binary ships prebuilt in its own package; nothing to compile in the sandbox.
  npmFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ makeWrapper ];

  # Reproduce the published npm layout (package.json `files`): the .ts extension
  # modules, the prebuilt JS bits, docs, and the production node_modules — so a
  # Pi install can point at $out/lib/pi-mcp-adapter and resolve bare imports.
  # Drop the dev-only test files and the 3 MB demo video, neither of which is in
  # the npm tarball.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/pi-mcp-adapter
    cp -r node_modules package.json cli.js app-bridge.bundle.js \
      README.md CHANGELOG.md LICENSE banner.png *.ts \
      $out/lib/pi-mcp-adapter/
    rm -f $out/lib/pi-mcp-adapter/*.test.ts $out/lib/pi-mcp-adapter/vitest.config.ts

    makeWrapper ${nodejs}/bin/node $out/bin/pi-mcp-adapter \
      --add-flags "$out/lib/pi-mcp-adapter/cli.js"

    runHook postInstall
  '';

  meta = {
    description = "MCP (Model Context Protocol) adapter extension for the Pi coding agent";
    homepage = "https://github.com/nicobailon/pi-mcp-adapter";
    changelog = "https://github.com/nicobailon/pi-mcp-adapter/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "pi-mcp-adapter";
    platforms = lib.platforms.unix;
  };

  passthru.updateScript = [
    ../_update/run.sh
    "--attr"
    "pi-mcp-adapter"
    "--use-github-releases"
    "--pre-hook"
    "regen-npm-lockfile:nicobailon/pi-mcp-adapter:v:omit-dev"
  ];
}
