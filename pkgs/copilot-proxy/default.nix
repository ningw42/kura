{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  makeWrapper,
}:

buildNpmPackage rec {
  pname = "copilot-proxy";
  version = "0.9.3";

  src = fetchFromGitHub {
    owner = "Jer-y";
    repo = "copilot-proxy";
    rev = "v${version}";
    hash = "sha256-YNK/7WCxOwZG8Y7V6Xb4nac3U4gRiBwoPg3vCw3O28c=";
  };

  # Upstream is a Bun project: it ships only `bun.lock`, no npm lockfile. We
  # vendor one regenerated with npm 10 (so transitive deps carry
  # `resolved`/`integrity`, which fetchNpmDeps requires) and drop it in here.
  # See pkgs/_update/hooks.sh (regen-npm-lockfile) for the matching update path.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json

    # changelogithub is only used by the upstream release script. Excluding it
    # keeps release tooling out of the build closure while preserving the
    # security overrides from upstream package.json.
    if command -v node >/dev/null; then
      node -e '
        const fs = require("fs");
        const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
        delete pkg.devDependencies.changelogithub;
        fs.writeFileSync("package.json", JSON.stringify(pkg));
      '
    fi
  '';

  npmDepsHash = "sha256-ygEgDzU+Jk5FGZ6RRB2Z4vlwPO0VCjclljSyYK9mOvA=";

  # `--ignore-scripts` blocks dependency lifecycle scripts (and the root
  # `prepare`/`prepack`, which would try to wire git hooks) during `npm ci`.
  # The explicit `npm run build` below still runs — npm only suppresses pre/post
  # hooks under this flag, not the named script. tsdown bundles via a prebuilt
  # rolldown native binary, so nothing needs compiling in the sandbox.
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];

  # `npm run build` runs tsdown, bundling src/main.ts -> dist/main.js (ESM,
  # node target). tsdown externalizes the runtime `dependencies`, so the bundle
  # still resolves them from a sibling node_modules at runtime.

  nativeBuildInputs = [ makeWrapper ];

  # Ship the bundled output plus a production-only node_modules (the dev
  # toolchain — tsdown/rolldown/eslint/typescript — is dead weight at runtime).
  installPhase = ''
    runHook preInstall

    # Drop dev deps from node_modules. `--no-save` keeps prune from rewriting
    # package-lock.json (copied read-only from the store in postPatch); the
    # writable cache keeps npm's log writes off the read-only deps store path.
    export npm_config_cache="$TMPDIR/.npm"
    npm prune --omit=dev --offline --ignore-scripts --legacy-peer-deps --no-save

    mkdir -p $out/lib/copilot-proxy
    cp -r dist node_modules package.json $out/lib/copilot-proxy/

    makeWrapper ${nodejs}/bin/node $out/bin/copilot-proxy \
      --add-flags "$out/lib/copilot-proxy/dist/main.js"

    runHook postInstall
  '';

  meta = {
    description = "Turn GitHub Copilot into an OpenAI/Anthropic-compatible server with Claude Code and Codex support";
    homepage = "https://github.com/Jer-y/copilot-proxy";
    changelog = "https://github.com/Jer-y/copilot-proxy/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "copilot-proxy";
    platforms = lib.platforms.unix;
  };

  passthru.updateScript = [
    ../_update/run.sh
    "--attr"
    "copilot-proxy"
    "--use-github-releases"
    "--pre-hook"
    "regen-npm-lockfile:Jer-y/copilot-proxy:v:legacy-peer-deps"
  ];
}
