{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  coreutils,
}:

buildGoModule (finalAttrs: {
  pname = "sing-box";
  version = "1.14.0";

  src = fetchFromGitHub {
    owner = "SagerNet";
    repo = "sing-box";
    # Pin via `rev` (bare tag), not `tag`, so nix-update doesn't re-fetch the
    # dependency hashes on every no-op update. See AGENTS.md ("rev vs tag").
    rev = "v${finalAttrs.version}";
    hash = "sha256-1v9bgM2H439ZoSkomv5dmT5SNrkuyOJ1iFFPlYPsW/k=";
  };

  vendorHash = "sha256-Bl73SkmnOyh5kULctDaxcOzXsYXRY2DOt80ME2+lBJo=";

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
    "sing-box"
    "--use-github-releases"
    "--post-hook"
    "sync-go-builder:SagerNet/sing-box:v"
  ];

  meta = {
    homepage = "https://sing-box.sagernet.org";
    description = "Universal proxy platform";
    license = lib.licenses.gpl3Plus;
    mainProgram = "sing-box";
  };
})
