{
  fetchurl,
  lib,
  nix-update-script,
  stdenvNoCC,
}:

let
  sources = {
    "x86_64-linux" = {
      artifact = "moshi-hook_Linux_x86_64.tar.gz";
      hash = "sha256-k0LTKbW/PBhPpfsbnA9+KVKK3bHllXQZHSCLXmetJHw=";
    };
    "aarch64-darwin" = {
      artifact = "moshi-hook_Darwin_arm64.tar.gz";
      hash = "sha256-FZH8IpM3ZmfBxtTrbYa04UdN3uMp3LeUjhtSgk2vHnY=";
    };
  };
in
stdenvNoCC.mkDerivation (
  finalAttrs:
  let
    # Fetch both platforms' artifacts with the current system's fetcher so
    # nix-update can refresh every hash without a builder for the other platform.
    artifacts = lib.mapAttrs (
      _: source:
      fetchurl {
        url = "https://cdn.getmoshi.app/hook/v${finalAttrs.version}/${source.artifact}";
        inherit (source) hash;
      }
    ) sources;
  in
  {
    pname = "moshi-hook";
    version = "0.3.30";

    src = artifacts.${stdenvNoCC.hostPlatform.system};

    sourceRoot = ".";
    dontPatchELF = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 moshi-hook "$out/bin/moshi-hook"
      ln -s moshi-hook "$out/bin/moshi"

      install -Dm644 README.md "$out/share/doc/moshi-hook/README.md"
      cp -r docs "$out/share/doc/moshi-hook/docs"

      runHook postInstall
    '';

    passthru = artifacts // {
      updateScript = nix-update-script {
        extraArgs = [
          "--flake"
          "--url"
          "https://github.com/rjyo/homebrew-moshi"
          "--use-github-releases"
          "--version-regex"
          "^v([0-9.]+)$"
          # src is already covered by the two platform fetchers below.
          "--no-src"
          "--custom-dep"
          "x86_64-linux"
          "--custom-dep"
          "aarch64-darwin"
        ];
      };
    };

    meta = {
      description = "Bridge local coding agents to Moshi";
      homepage = "https://getmoshi.app/docs/install-moshi-hook";
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      license = lib.licenses.unfree;
      mainProgram = "moshi-hook";
      platforms = builtins.attrNames sources;
    };
  }
)
