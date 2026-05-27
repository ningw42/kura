{
  lib,
  stdenv,
  stdenvNoCC,
  buildGo125Module,
  fetchFromGitHub,
  fetchYarnDeps,
  yarnConfigHook,
  yarnBuildHook,
  yarnInstallHook,
  nodejs,
  yarn,
  pkg-config,
  vips,
  makeWrapper,
}:

let
  pname = "koito";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "gabehf";
    repo = "koito";
    rev = "v${version}";
    hash = "sha256-qDQYVg/adZwGT5O+vSFd2HeSukpDXcalFXtILaP7QbI=";
  };

  # Frontend build: react-router (Vite) bundle in client/build/client.
  frontend = stdenvNoCC.mkDerivation {
    pname = "${pname}-frontend";
    inherit version;

    src = "${src}/client";

    nativeBuildInputs = [
      yarnConfigHook
      yarnBuildHook
      yarnInstallHook
      nodejs
      yarn
    ];

    yarnOfflineCache = fetchYarnDeps {
      yarnLock = "${src}/client/yarn.lock";
      hash = "sha256-vnddE1H3FROkvh7tL0MzkSbsS9Na2s6oy5rIBhJtM9M=";
    };

    env = {
      VITE_KOITO_VERSION = version;
      BUILD_TARGET = "docker";
    };

    # yarnInstallHook copies node_modules + everything; we only need the build/ output.
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r build $out/build
      cp -r public $out/public
      runHook postInstall
    '';

    dontFixup = true;
  };

  backend = buildGo125Module {
    pname = "${pname}-bin";
    inherit version src;

    vendorHash = "sha256-KuGNUqKWYyLykfsRdwao6jI5nvD+u95XFxo2EfOJeJg=";

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
      #   koito.frontend -> yarnOfflineCache.outputHash (nix-update native)
      "--attr"
      "koito.backend"
      "--attr"
      "koito.frontend"
      "--use-github-releases"
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
