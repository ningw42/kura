{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nix-update-script,
}:

buildNpmPackage (finalAttrs: {
  pname = "pi-distribution";
  version = "0-unstable-2026-08-07";

  src = fetchFromGitHub {
    owner = "ningw42";
    repo = "pi-distribution";
    rev = "8cc0e6dc0f544339176c86719af3377d8468a1f0";
    hash = "sha256-Y/R5idp9l0l44HXWfvQuPJHnteSiA5zxORsPAIm9XMY=";
  };

  # pi-cc-extensions bundles this dependency inside its npm tarball, so npm 11
  # omits the nested package's resolved URL from the aggregate lockfile. Add the
  # canonical URL so fetchNpmDeps can also seed npm's offline packument cache.
  postPatch = ''
    substituteInPlace package-lock.json \
      --replace-fail \
        '"version": "0.2.5",' \
        '"version": "0.2.5",
      "resolved": "https://registry.npmjs.org/@tifan/pi-fixed-editor/-/pi-fixed-editor-0.2.5.tgz",
      "integrity": "sha512-54Vfj1K+RxBBGFA7wJ+INWRtpefa2jTNRgmc9xWddS2upI1gHYqtGQQz+xPVmaP/X6cys8PB+dWWMXkZmO/73Q==",'
  '';

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-BdcfsBvhTdnJiughC4vuD3+gqLHLJ/Glzwe16HkZymA=";

  # The package ships TypeScript extensions directly for Pi to load.
  dontNpmBuild = true;

  # None of the production dependencies needs a lifecycle script. Pi provides
  # the optional peer packages at runtime.
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
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
      "--version=branch"
    ];
  };

  meta = {
    description = "Aggregate package of Pi extensions, skills, and themes";
    homepage = "https://github.com/ningw42/pi-distribution";
    changelog = "https://github.com/ningw42/pi-distribution/commits/main";
    platforms = lib.platforms.unix;
  };
})
