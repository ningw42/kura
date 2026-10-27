{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  git,
  nix-update-script,
}:

buildNpmPackage (finalAttrs: {
  pname = "pi-distribution";
  version = "26.10.34";

  src = fetchFromGitHub {
    owner = "ningw42";
    repo = "pi-distribution";
    rev = "v${finalAttrs.version}";
    hash = "sha256-EHPCwsysVxeHbLhNNmBawIUEnizr9t5oERwp5p7J20E=";
  };

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-o5Wx91IIsm+9ih39hqLhEV95DyYx4FY50Vr5K8Ibpz4=";

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

  # Updater regression tests create real Git repositories.
  nativeCheckInputs = [ git ];

  doCheck = true;
  # Runtime-coupled tests use the separately locked smoke environment, which
  # is intentionally excluded from this package's production dependency closure.
  checkPhase = ''
    runHook preCheck

    npm run test:package

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
