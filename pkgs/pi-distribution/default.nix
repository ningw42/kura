{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nix-update-script,
}:

buildNpmPackage (finalAttrs: {
  pname = "pi-distribution";
  version = "26.09.13";

  src = fetchFromGitHub {
    owner = "ningw42";
    repo = "pi-distribution";
    rev = "v${finalAttrs.version}";
    hash = "sha256-PCuevvo7PgFiwBUARRLP8wuhlU9yHGw7fMuhGsK4i40=";
  };

  # npm follows this short pkg.pr.new dependency edge instead of reusing the
  # canonical resolved entry, which fetchNpmDeps caches for offline installs.
  # Remove this workaround once pi-mcp-adapter's MCP client dependency no
  # longer uses the repository-style URL below (for example, after returning
  # to a registry release), then refresh npmDepsHash and verify the package
  # build. --replace-fail deliberately flags an upstream lockfile change.
  postPatch = ''
    substituteInPlace package-lock.json \
      --replace-fail \
      "https://pkg.pr.new/modelcontextprotocol/typescript-sdk/@modelcontextprotocol/core@3b205e7" \
      "https://pkg.pr.new/@modelcontextprotocol/core@3b205e7dd2f997b6a87e479e36421f7eaa2058e0"
  '';

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-Buawh5Rln7MMkFIOPRrZrK+DRuCQT/J4gpqQdRDALN0=";

  # The package ships TypeScript extensions directly for Pi to load.
  dontNpmBuild = true;

  # None of the production dependencies needs a lifecycle script. Pi provides
  # the optional peer packages at runtime, and upstream's dev dependency is only
  # needed for its smoke test.
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
    "--omit=dev"
  ];

  doCheck = true;
  # Runtime-coupled tests use the separately locked smoke environment, which
  # is intentionally excluded from this package's production dependency closure.
  # v26.09.13 predates the upstream production-only test command; retain its
  # equivalent fallback until the package pin advances.
  checkPhase = ''
    runHook preCheck

    if node -e 'process.exit("test:package" in require("./package.json").scripts ? 0 : 1)'; then
      npm run test:package
    else
      node --test tests/validate-npm-update.test.mjs
      npm run check
    fi

    runHook postCheck
  '';

  # Preserve a stable Pi package root containing the aggregate manifest and
  # every resource path it declares.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/pi-distribution
    cp -r extensions vendor node_modules package.json \
      README.md NOTICE.md $out/lib/pi-distribution/

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };

  meta = {
    description = "Aggregate package of Pi extensions, skills, and themes";
    homepage = "https://github.com/ningw42/pi-distribution";
    changelog = "https://github.com/ningw42/pi-distribution/releases/tag/v${finalAttrs.version}";
    platforms = lib.platforms.unix;
  };
})
