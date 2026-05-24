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
}
