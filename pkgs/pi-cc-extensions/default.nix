{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "pi-cc-extensions";
  version = "0.8.44";

  src = fetchFromGitHub {
    owner = "minuque";
    repo = "pi-cc-extensions";
    rev = "v${version}";
    hash = "sha256-xsjkhm7UfEeHlOhcU6YVJru8VmoG2Lhrl2LYyCiOBmE=";
  };

  # Pi supplies the @earendil-works peer packages at runtime. Keep only the
  # extension's direct runtime dependencies and omit upstream's test/typecheck
  # toolchain; the matching update hook regenerates this production-only lock.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    if command -v node >/dev/null; then
      node --eval 'const fs = require("fs"); const p = JSON.parse(fs.readFileSync("package.json")); delete p.devDependencies; fs.writeFileSync("package.json", JSON.stringify(p, null, 2));'
    fi
  '';

  npmDepsHash = "sha256-tY1yICQHPeAmuULa0qUrJYrkFrJFLSwaf4sKCob1LEU=";

  # Pi loads the TypeScript extension directly; upstream has no build output.
  dontNpmBuild = true;

  # Peer dependencies come from Pi. The production dependencies are plain
  # JavaScript packages and do not need lifecycle scripts.
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];

  # Preserve the Pi package root so package.json registers both the composite
  # extension and its two bundled themes, with bare imports resolved locally.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/pi-cc-extensions
    cp -r extensions themes node_modules package.json \
      README.md README.en.md LICENSE \
      $out/lib/pi-cc-extensions/

    runHook postInstall
  '';

  meta = {
    description = "Claude Code-style UI and productivity extension suite for the Pi coding agent";
    homepage = "https://github.com/minuque/pi-cc-extensions";
    changelog = "https://github.com/minuque/pi-cc-extensions/releases/tag/v${version}";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };

  passthru.updateScript = [
    ../_update/run.sh
    "--attr"
    "pi-cc-extensions"
    "--use-github-releases"
    "--pre-hook"
    "regen-npm-lockfile:minuque/pi-cc-extensions:v:legacy-peer-deps,omit-dev"
  ];
}
