{
  buildHomeAssistantComponent,
  fetchFromGitHub,
}:

buildHomeAssistantComponent rec {
  owner = "PiotrMachowski";
  domain = "smartthings_soundbar";
  version = "1.0.4";

  src = fetchFromGitHub {
    owner = "PiotrMachowski";
    repo = "Home-Assistant-custom-components-SmartThings-Soundbar";
    rev = "v${version}";
    hash = "sha256-6nfEAQWcyxskszTL9mNXvv3jgzxOi1T4kIefuHD52Y8=";
  };

  dontBuild = true;

  # buildHomeAssistantComponent inherits an updateScript from its base, but
  # (a) it's not --flake aware and (b) the pname is `<owner>/<domain>` which
  # the nixpkgs update runner can't use as a log filename. Clear it so we
  # never get picked up by `nix run .#update`.
  passthru.updateScript = null;
}
