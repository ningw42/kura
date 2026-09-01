{
  fetchFromGitHub,
  buildGo126Module,
}:

buildGo126Module rec {
  pname = "telepush";
  version = "4.2.2";

  src = fetchFromGitHub {
    owner = "muety";
    repo = "telepush";
    rev = version;
    hash = "sha256-g21UVo/fHpOUClUoay6eM+H1d30Bn18fWqhUSJs+2s0=";
  };

  vendorHash = "sha256-ov36gbMmdQb8UFL70Ys0C5hZ+356MTf5PUtAIdR/xIU=";

  passthru.updateScript = [
    ../_update/run.sh
    "--attr"
    "telepush"
    "--use-github-releases"
    "--pre-hook"
    "sync-go-builder:muety/telepush:"
  ];
}
