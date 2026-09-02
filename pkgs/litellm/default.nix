{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  nix-update-script,
  rustPlatform,
  aiohttp,
  click,
  fastuuid,
  httpx,
  importlib-metadata,
  jinja2,
  jsonschema,
  openai,
  pydantic,
  python-dotenv,
  requests,
  tiktoken,
  tokenizers,
  apscheduler,
  azure-identity,
  azure-storage-blob,
  backoff,
  boto3,
  cryptography,
  fastapi,
  fastapi-sso,
  gunicorn,
  mcp,
  orjson,
  pyjwt,
  pynacl,
  python-multipart,
  pyyaml,
  restrictedpython,
  rich,
  rq,
  soundfile,
  uvloop,
  uvicorn,
  websockets,
}:

buildPythonPackage rec {
  pname = "litellm";
  version = "1.99.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "BerriAI";
    repo = "litellm";
    # Pin via `rev` (bare tag), not `tag`, so nix-update doesn't re-fetch the
    # dependency hashes on every no-op update. See AGENTS.md ("rev vs tag").
    rev = "v${version}";
    hash = "sha256-BoiHgcGX4MIHYTWSQRfbuAdCPxuUXttYN1my4WgAtZ8=";
  };

  cargoRoot = "litellm-rust";

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = "${src}/litellm-rust/Cargo.lock";
  };

  build-system = with rustPlatform; [
    cargoSetupHook
    maturinBuildHook
  ];

  dependencies = [
    aiohttp
    click
    fastuuid
    httpx
    importlib-metadata
    jinja2
    jsonschema
    openai
    pydantic
    python-dotenv
    requests
    tiktoken
    tokenizers
  ];

  optional-dependencies = {
    proxy = [
      apscheduler
      azure-identity
      azure-storage-blob
      backoff
      boto3
      cryptography
      fastapi
      fastapi-sso
      gunicorn
      mcp
      orjson
      pyjwt
      pynacl
      python-multipart
      pyyaml
      restrictedpython
      rich
      rq
      soundfile
      uvloop
      uvicorn
      websockets
    ];
  };

  pythonImportsCheck = [
    "litellm"
  ];

  pythonRelaxDeps = true;

  doCheck = false;

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
      "--version-regex"
      "^v?([0-9]+\\.[0-9]+\\.[0-9]+)$"
    ];
  };

  meta = {
    description = "Use any LLM as a drop in replacement for gpt-3.5-turbo";
    mainProgram = "litellm";
    homepage = "https://github.com/BerriAI/litellm";
    changelog = "https://github.com/BerriAI/litellm/releases/tag/v${version}";
    license = lib.licenses.mit;
  };
}
