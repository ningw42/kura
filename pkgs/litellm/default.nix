{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  uv-build,
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
  version = "1.86.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "BerriAI";
    repo = "litellm";
    tag = "v${version}";
    hash = "sha256-uInjKBUduDAfXHg5dQj5/qqqMJhlDeTri1kULkz5unM=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires = ["uv_build==0.11.8"]' 'requires = ["uv_build>=0.10.0"]'
  '';

  build-system = [ uv-build ];

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

  meta = {
    description = "Use any LLM as a drop in replacement for gpt-3.5-turbo";
    mainProgram = "litellm";
    homepage = "https://github.com/BerriAI/litellm";
    changelog = "https://github.com/BerriAI/litellm/releases/tag/${src.tag}";
    license = lib.licenses.mit;
  };
}
