{
  lib,
  stdenv,
  tmux,
  hexdump,
  fetchFromGitHub,
  installShellFiles,
  nix-update-script,
  runtimeShell,
  rustPlatform,
  skim,
  testers,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "skim";
  version = "4.9.0";

  outputs = [
    "out"
    "man"
    "vim"
  ];

  src = fetchFromGitHub {
    owner = "skim-rs";
    repo = "skim";
    # Pin via `rev` (bare tag), not `tag`, so nix-update doesn't re-fetch the
    # dependency hashes on every no-op update. See AGENTS.md ("rev vs tag").
    rev = "v${finalAttrs.version}";
    hash = "sha256-LsIR0FgS+Ak+Hoh2UBODjTNfK3M0GVJnkaa2LRiGoJM=";
  };

  postPatch = ''
    sed -i -e "s|expand('<sfile>:h:h')|'$out'|" plugin/skim.vim
  '';

  cargoHash = "sha256-Ee3WtdsZg1hekDpZTzZW0GwttPB7I3lipxe//kiSits=";

  nativeBuildInputs = [ installShellFiles ];
  nativeCheckInputs = [
    tmux
    hexdump
  ];

  postBuild = ''
    cat <<SCRIPT > sk-share
    #! ${runtimeShell}
    # Run this script to find the skim shared folder where all the shell
    # integration scripts are living.
    echo $out/share/skim
    SCRIPT
  '';

  postInstall = ''
    installBin bin/sk-tmux
    install -D -m 444 plugin/skim.vim -t $vim/plugin
    install -D -m 444 shell/* -t $out/share/skim

    installBin sk-share
    installManPage $(find man -type f)
    installShellCompletion \
      --cmd sk \
      --bash shell/completion.bash \
      --fish shell/completion.fish \
      --zsh shell/completion.zsh
  '';

  # The `skim::listen` tests spawn bash subshells that try to source
  # /etc/bashrc; the Nix sandbox on Darwin denies that ("Operation not
  # permitted"), the bash session never delivers input to the listen socket,
  # and all 30 tests time out. Upstream CI runs these on macos-latest without
  # the sandbox, so it isn't a skim bug — re-enable once we filter out just
  # the listen tests (or upstream gains a sandbox-friendly path).
  doCheck = !stdenv.hostPlatform.isDarwin;

  useNextest = true;

  checkPhase = ''
    cargo nextest run --release --offline --lib --bins --examples --tests
  '';

  passthru = {
    tests.version = testers.testVersion { package = skim; };
    updateScript = nix-update-script {
      extraArgs = [
        "--flake"
        "--use-github-releases"
      ];
    };
  };

  meta = {
    description = "Command-line fuzzy finder written in Rust";
    homepage = "https://github.com/skim-rs/skim";
    changelog = "https://github.com/skim-rs/skim/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "sk";
  };
})
