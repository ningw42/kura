{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  makeWrapper,
}:

buildNpmPackage {
  pname = "copilot-proxy";
  # Fork of Jer-y/copilot-proxy tracking the feat/codex-auto-review-alias
  # branch (2 commits ahead of v0.7.16, no tag). The `-unstable-<date>` suffix
  # is the commit date of the pinned rev below.
  version = "0.7.16-unstable-2026-07-10";

  src = fetchFromGitHub {
    owner = "ningw42";
    repo = "copilot-proxy";
    # Branch HEAD, not a tag: pin the exact commit. Bump rev + hash + the
    # `-unstable-` date together when new commits land on the branch.
    rev = "b23f6a6b842eab816b50a0a3cee1affd6c3e4e8d";
    hash = "sha256-VFlsg+0Dy08lq64rdnb6naYcWBdYomoV9UErZk5R7Rk=";
  };

  # Upstream is a Bun project: it ships only `bun.lock`, no npm lockfile. We
  # vendor one regenerated with npm 10 (so transitive deps carry
  # `resolved`/`integrity`, which fetchNpmDeps requires) and drop it in here.
  # The updater is disabled (see passthru.updateScript below), so regenerate
  # this by hand when deps change — pkgs/_update/hooks.sh (regen-npm-lockfile)
  # is the recipe.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-54NgnVKMylwOabK8eO9n+sJ73PdUE/i2pOH+CocG5Ok=";

  # `--ignore-scripts` blocks dependency lifecycle scripts (and the root
  # `prepare`/`prepack`, which would try to wire git hooks) during `npm ci`.
  # The explicit `npm run build` below still runs — npm only suppresses pre/post
  # hooks under this flag, not the named script. tsdown bundles via a prebuilt
  # rolldown native binary, so nothing needs compiling in the sandbox.
  npmFlags = [ "--ignore-scripts" ];

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
    npm prune --omit=dev --offline --ignore-scripts --no-save

    mkdir -p $out/lib/copilot-proxy
    cp -r dist node_modules package.json $out/lib/copilot-proxy/

    makeWrapper ${nodejs}/bin/node $out/bin/copilot-proxy \
      --add-flags "$out/lib/copilot-proxy/dist/main.js"

    runHook postInstall
  '';

  meta = {
    description = "Turn GitHub Copilot into an OpenAI/Anthropic-compatible server with Claude Code and Codex support";
    homepage = "https://github.com/ningw42/copilot-proxy";
    changelog = "https://github.com/ningw42/copilot-proxy/commit/b23f6a6b842eab816b50a0a3cee1affd6c3e4e8d";
    license = lib.licenses.mit;
    mainProgram = "copilot-proxy";
    platforms = lib.platforms.unix;
  };

  # Disabled: this pins a personal fork's feature-branch HEAD, not a release.
  # The shared driver discovers versions from GitHub releases and its
  # regen-npm-lockfile hook clones a tag — neither fits a branch snapshot. Bump
  # src.rev/hash + the version date by hand (regen package-lock.json via the
  # regen-npm-lockfile recipe if deps change).
  passthru.updateScript = null;
}
