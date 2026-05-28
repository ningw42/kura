{
  lib,
  stdenvNoCC,
  buildGo125Module,
  fetchFromGitHub,
  yarn-berry_4,
  nodejs,
  pkg-config,
  vips,
  makeWrapper,
}:

let
  pname = "koito";
  version = "0.3.1";

  src = fetchFromGitHub {
    owner = "gabehf";
    repo = "koito";
    rev = "v${version}";
    hash = "sha256-p+FzeFQ8zMOcQCwo2eyNfW9ne+fC/jjbx2WKRrxTFjc=";
  };

  # Frontend build: react-router (Vite) bundle in client/build/client.
  # Upstream switched to Yarn 4 (Berry) in 0.3.x — lockfile is __metadata: v9.
  frontend = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "${pname}-frontend";
    inherit version;

    src = "${src}/client";

    nativeBuildInputs = [
      yarn-berry_4.yarnBerryConfigHook
      yarn-berry_4
      nodejs
    ];

    # Berry equivalent of fetchYarnDeps. nix-update's `eval.nix` looks up
    # `pkg.yarnOfflineCache.outputHash or pkg.offlineCache.outputHash`, so
    # the canonical berry name `offlineCache` works without changes upstream.
    missingHashes = ./missing-hashes.json;
    offlineCache = yarn-berry_4.fetchYarnBerryDeps {
      inherit (finalAttrs) src missingHashes;
      hash = "sha256-VIlWld21GScJ/2UUkKQISM9jyU9wCVwwDNKkge+K044=";
    };

    env = {
      VITE_KOITO_VERSION = version;
      BUILD_TARGET = "docker";
    };

    buildPhase = ''
      runHook preBuild
      yarn run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r build $out/build
      cp -r public $out/public
      runHook postInstall
    '';

    dontFixup = true;
  });

  backend = buildGo125Module {
    pname = "${pname}-bin";
    inherit version src;

    vendorHash = "sha256-W/+ByBlEPd4yIUD/E28q93fz6wYgvhwyBvJL8Fm1lNY=";

    subPackages = [ "cmd/api" ];

    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ vips ];

    env.CGO_ENABLED = "1";

    ldflags = [
      "-s"
      "-w"
      "-X main.Version=${version}"
    ];

    # Tests need a database/network and some are heavy; skip.
    doCheck = false;

    postInstall = ''
      mv $out/bin/api $out/bin/koito
    '';
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/koito/client $out/share/koito/assets

    # Frontend bundle and static public files.
    cp -r ${frontend}/build $out/share/koito/client/build
    cp -r ${frontend}/public $out/share/koito/client/public

    # Runtime assets (default image, fonts) loaded relative to the cwd.
    cp -r ${src}/assets/. $out/share/koito/assets/

    # Wrap the binary so it always runs from a directory layout that matches
    # what the upstream Dockerfile sets up (cwd contains client/, assets/).
    makeWrapper ${backend}/bin/koito $out/bin/koito \
      --chdir $out/share/koito

    runHook postInstall
  '';

  passthru = {
    inherit frontend backend;
    updateScript = [
      ../_update/run.sh
      # Two attrs so nix-update updates each set of hashes:
      #   koito.backend  -> shared version, src.hash, vendorHash
      #   koito.frontend -> offlineCache.outputHash (nix-update native)
      "--attr"
      "koito.backend"
      "--attr"
      "koito.frontend"
      "--use-github-releases"
      # Pre-hook: refresh missing-hashes.json for the new yarn.lock BEFORE
      # nix-update prefetches the offline cache, since the cache's output
      # hash depends on both files.
      "--pre-hook"
      "regen-yarn-berry-missing-hashes:gabehf/koito:v:client/yarn.lock"
      "--post-hook"
      "sync-go-builder:gabehf/koito:v"
    ];
  };

  meta = {
    description = "Modern, themeable ListenBrainz-compatible scrobbler for self-hosters";
    homepage = "https://github.com/gabehf/koito";
    license = lib.licenses.mit;
    mainProgram = "koito";
    platforms = lib.platforms.linux;
  };
}
