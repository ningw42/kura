{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "pi-subagents";
  version = "0.14.3";

  src = fetchFromGitHub {
    owner = "tintinweb";
    repo = "pi-subagents";
    rev = "v${version}";
    hash = "sha256-ZztgK9TUrpLsTSmYTOlHu8f6P5G/EA3MmVhqSfFZLQA=";
  };

  # Keep only the extension's direct runtime dependencies. Pi supplies the
  # @earendil-works peer packages when it loads the extension, while the
  # TypeScript, Biome, and Vitest dependencies are only upstream tooling.
  # The matching update hook regenerates this production-only lockfile.
  #
  # Also point Pi at the root shim installed below. Upstream declares
  # `src/index.ts`, which makes Pi label the extension `src` in its startup
  # banner; a root `index.ts` makes the stable package directory supply the
  # intended `pi-subagents` label instead.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    if command -v node >/dev/null; then
      node --eval 'const fs = require("fs"); const p = JSON.parse(fs.readFileSync("package.json")); delete p.devDependencies; p.pi.extensions = ["./index.ts"]; fs.writeFileSync("package.json", JSON.stringify(p, null, 2));'
    fi
  '';

  npmDepsHash = "sha256-7mXw5eYqxF8GyAjRW6GlpdZOzVHqj9coJtpZPY1oM+w=";

  # Pi loads the TypeScript sources directly, so there is no build output.
  dontNpmBuild = true;

  # Peer dependencies come from Pi rather than this package. No dependency in
  # the production closure needs an install script.
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/pi-subagents
    cp -r src examples node_modules package.json \
      README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md LICENSE \
      $out/lib/pi-subagents/
    cat > $out/lib/pi-subagents/index.ts <<'EOF'
    export { default } from "./src/index.js";
    EOF

    runHook postInstall
  '';

  meta = {
    description = "Claude Code-style autonomous subagents for the Pi coding agent";
    homepage = "https://github.com/tintinweb/pi-subagents";
    changelog = "https://github.com/tintinweb/pi-subagents/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };

  passthru.updateScript = [
    ../_update/run.sh
    "--attr"
    "pi-subagents"
    "--use-github-releases"
    "--pre-hook"
    "regen-npm-lockfile:tintinweb/pi-subagents:v:legacy-peer-deps,omit-dev"
  ];
}
