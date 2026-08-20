{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nix-update-script,
}:

buildNpmPackage (finalAttrs: {
  pname = "pi-distribution";
  version = "26.08.18";

  src = fetchFromGitHub {
    owner = "ningw42";
    repo = "pi-distribution";
    rev = "v${finalAttrs.version}";
    hash = "sha256-A8jsKYEuYYaYFD3oboQasmV0Wh80EtS9FFVWuKr11wE=";
  };

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-rFBu+R2sbJGBQhTVUcIFmrnesI88b0glDc/SICUvYDo=";

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
  checkPhase = ''
    runHook preCheck

    npm test

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
