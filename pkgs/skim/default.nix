{
  lib,
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
  version = "5.5.0";

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
    hash = "sha256-Ykz7zVqNiWWhyqCLCtHlUXt56M2jxGnKy0eCpbQx988=";
  };

  postPatch = ''
    sed -i -e "s|expand('<sfile>:h:h')|'$out'|" plugin/skim.vim
  '';

  cargoHash = "sha256-lw8hNFaBkpPdN2h2qZzNF19I+giIPpazYlFkjMc3GyI=";

  nativeBuildInputs = [ installShellFiles ];

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

  # We pin released upstream tags, and skim's own CI already runs this exact
  # suite (`cargo nextest run --release … --lib --bins --examples --tests`)
  # across Linux/macOS/Windows before every release, so re-running it here only
  # duplicates that work — and it dominates a cold build: skim's release profile
  # (`lto = true`, `codegen-units = 1`) makes compiling the test/example
  # binaries take ~21 min vs. ~5 min for the `sk` binary itself. A build failure
  # still surfaces any nixpkgs-toolchain breakage, and `passthru.tests.version`
  # smoke-tests the installed binary. Restore the test run if we ever ship a
  # patched or unreleased rev.
  doCheck = false;

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
