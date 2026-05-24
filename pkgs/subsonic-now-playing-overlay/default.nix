{
  buildNpmPackage,
  fetchFromGitHub,
}:

# to build this pkg, the running user account needs ssh access to my GitHub
buildNpmPackage rec {
  pname = "subsonic-now-playing-overlay";
  version = "dda1acf9895f65afb133df6cbcc8dc85332f9b72";

  src = fetchFromGitHub {
    owner = "ningw42";
    repo = "SubsonicNowPlayingOverlay";
    rev = version;
    hash = "sha256-l42PleUY6k6gS1bVvtMXfTb/uF5XO19Ic/sD2Xdzhjg=";
  };

  # the output of the dependencies
  npmDepsHash = "sha256-im59ePS3XXRjITBK7WHWKg7YAoIUpLjFIiIKuv4lhfs=";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share
    cp -a . $out/share/subsonic-now-playing-overlay

    runHook postInstall
  '';
}
