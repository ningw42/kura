{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  coreutils,
}:

buildGoModule (finalAttrs: {
  pname = "sing-box-alpha";
  version = "1.14.0-alpha.26";

  src = fetchFromGitHub {
    owner = "SagerNet";
    repo = "sing-box";
    tag = "v${finalAttrs.version}";
    hash = "sha256-NQOsJFSzbTTQtYzOpZmh7J2XkfUFpIHSQQ51MjV2kUE=";
  };

  vendorHash = "sha256-RFgMu8rlqcAUWagMR++etRLzMFWzwfeDnOCWmAuDH3I=";

  tags = [
    "with_gvisor"
    "with_quic"
    "with_dhcp"
    "with_wireguard"
    "with_utls"
    "with_acme"
    "with_clash_api"
    "with_tailscale"
    "with_ccm"
    "with_ocm"
    "badlinkname"
    "tfogo_checklinkname0"
  ];

  subPackages = [
    "cmd/sing-box"
  ];

  env.CGO_ENABLED = 0;

  nativeBuildInputs = [ installShellFiles ];

  ldflags = [
    "-X=github.com/sagernet/sing-box/constant.Version=${finalAttrs.version}"
    "-X=internal/godebug.defaultGODEBUG=multipathtcp=0"
    "-checklinkname=0"
  ];

  postInstall = ''
    installShellCompletion release/completions/sing-box.{bash,fish,zsh}

    substituteInPlace release/config/sing-box{,@}.service \
      --replace-fail "/usr/bin/sing-box" "$out/bin/sing-box" \
      --replace-fail "/bin/kill" "${coreutils}/bin/kill"
    install -Dm444 -t "$out/lib/systemd/system/" release/config/sing-box{,@}.service

    install -Dm444 release/config/sing-box.rules $out/share/polkit-1/rules.d/sing-box.rules
    install -Dm444 release/config/sing-box-split-dns.xml $out/share/dbus-1/system.d/sing-box-split-dns.conf
  '';

  passthru.updateScript = [
    ../_update/run.sh
    "--attr"
    "sing-box-alpha"
    "--use-github-releases"
    "--version"
    "unstable"
    # Pin to the current alpha series (1.14.*-alpha.*), with a capture group
    # so nix-update can extract the version from the matched tag.
    "--version-regex"
    "^v?(1\\.14\\.[0-9]+-alpha\\.[0-9]+)$"
    "--post-hook"
    "sync-go-builder:SagerNet/sing-box:v"
  ];

  meta = {
    homepage = "https://sing-box.sagernet.org";
    description = "Universal proxy platform (1.14 alpha)";
    license = lib.licenses.gpl3Plus;
    mainProgram = "sing-box";
  };
})
