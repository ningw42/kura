{
  lib,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  protobuf,
  pkg-config,
  perl,
  go,
  git,
  openssl,
  stdenv,
  nix-update-script,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "byokey";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "AprilNEA";
    repo = "BYOKEY";
    # Use `rev` rather than `tag`: fetchFromGitHub normalizes `tag` to
    # `src.rev = "refs/tags/v…"`, but nix-update's --use-github-releases
    # fetcher reports the new rev as the bare tag name ("v…"). The mismatch
    # makes nix-update think the rev changed on every run, forcing a full
    # cargoDeps re-vendor even when the version is unchanged. Pinning `rev`
    # to the bare tag keeps both sides equal, so hashes are only recomputed
    # on an actual version bump.
    rev = "v${finalAttrs.version}";
    hash = "sha256-w0kjdyTX7de0+HjJ160EYMwzoWYf+G6MFNTuj1kJNik=";
  };

  # Vendored from crates.io (no git sources in Cargo.lock).
  cargoHash = "sha256-AYUeqDN/Sqavf4WhgG7ddD9lH7abWngl2oetD4o+0EM=";

  # The desktop Tauri crate is excluded from the workspace; build only the
  # `byokey` binary and its workspace member crates.
  cargoBuildFlags = [
    "--bin"
    "byokey"
  ];

  nativeBuildInputs = [
    # protoc: byokey-proto/build.rs generates ConnectRPC code at build time.
    protobuf
    # cmake: vendored BoringSSL (boring-sys2) and aws-lc-sys.
    cmake
    # libclang for aws-lc-sys / bindgen.
    rustPlatform.bindgenHook
    # perl: openssl-sys vendored build invokes Configure.
    perl
    # git: boring-sys2 runs `git init` + applies patches to vendored BoringSSL.
    git
    # go: BoringSSL's CMake build generates sources with go.
    go
    pkg-config
  ];

  buildInputs = [ openssl ];

  # protoc location for connectrpc-build (reads PROTOC if set).
  PROTOC = "${protobuf}/bin/protoc";

  # The test suite reaches the network (OAuth credential fetch from
  # assets.byokey.io, upstream provider calls) and touches ~/.byokey; skip it.
  doCheck = false;

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };

  meta = {
    description = "Bring Your Own Keys — AI subscription-to-API proxy gateway";
    longDescription = ''
      BYOKEY is a Rust gateway that exposes LLM API endpoints
      (/v1/chat/completions, /v1/messages, /v1/responses) backed by your
      existing AI subscriptions (GitHub Copilot, Claude, Codex, Gemini),
      handling OAuth token lifecycle and multi-account routing.
    '';
    homepage = "https://github.com/AprilNEA/BYOKEY";
    changelog = "https://github.com/AprilNEA/BYOKEY/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "byokey";
    platforms = lib.platforms.unix;
  };
})
