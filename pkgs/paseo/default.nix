{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  python3,
  makeWrapper,
  autoPatchelfHook,
  libuv,
  nix-update-script,
}:

buildNpmPackage rec {
  pname = "paseo";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "getpaseo";
    repo = "paseo";
    rev = "v${version}";
    hash = "sha256-XV38ZFN7wEDkIIEQR/wchASURl9WGA40hNlg7d0/Hf8=";
  };

  nodejs = nodejs_22;
  npmDepsHash = "sha256-i5PbVUe2Ec+GtghV9IpCJQJ9hcUT5hFhmxneNvoD584=";

  # onnxruntime-node's install script downloads from api.nuget.org. Rebuild
  # only node-pty below; the speech runtime ships prebuilt platform packages.
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    python3
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libuv
    stdenv.cc.cc.lib
  ];

  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild

    npm rebuild node-pty
    npm run build:server
    npm run build:daemon-web-ui

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/paseo
    node scripts/trace-daemon.mjs > daemon-files.txt

    while IFS= read -r path; do
      [ -z "$path" ] && continue
      mkdir -p "$out/lib/paseo/$(dirname "$path")"
      cp -a "$path" "$out/lib/paseo/$path"
    done < daemon-files.txt

    cp package.json $out/lib/paseo/
    cp -r packages/server/dist/server/web-ui $out/lib/paseo/packages/server/dist/server/

    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/paseo-server \
      --add-flags "$out/lib/paseo/packages/server/dist/scripts/supervisor-entrypoint.js" \
      --set PASEO_NODE_ENV production
    makeWrapper ${nodejs}/bin/node $out/bin/paseo \
      --add-flags "$out/lib/paseo/packages/cli/dist/index.js" \
      --set NODE_PATH "$out/lib/paseo/node_modules"

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };

  meta = {
    description = "Self-hosted daemon for Claude Code, Codex, and OpenCode";
    homepage = "https://github.com/getpaseo/paseo";
    changelog = "https://github.com/getpaseo/paseo/releases/tag/v${version}";
    license = lib.licenses.agpl3Plus;
    mainProgram = "paseo";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
