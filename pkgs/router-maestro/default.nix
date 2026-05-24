{
  lib,
  python3Packages,
  fetchFromGitHub,
  installShellFiles,
  nix-update-script,
}:

python3Packages.buildPythonApplication rec {
  pname = "router-maestro";
  version = "0.3.15";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "MadSkittles";
    repo = "Router-Maestro";
    rev = "v${version}";
    hash = "sha256-0WypW8eyH8crw/PGLBDff3G+QKZWc56R34XLqJs9Gzs=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    typer
    rich
    fastapi
    uvicorn
    httpx
    h2
    pydantic
    pydantic-settings
    authlib
    tiktoken
    anthropic
    plotext
    aiosqlite
    python-dotenv
    tomlkit
    rapidfuzz
  ];

  nativeBuildInputs = [ installShellFiles ];

  postInstall =
    let
      completionScript = shell: ''
        ${python3Packages.python.interpreter} -c "from typer._completion_shared import get_completion_script; print(get_completion_script(prog_name='router-maestro', complete_var='_ROUTER_MAESTRO_COMPLETE', shell='${shell}'))"
      '';
    in
    ''
      installShellCompletion --cmd router-maestro \
        --bash <(${completionScript "bash"}) \
        --zsh <(${completionScript "zsh"}) \
        --fish <(${completionScript "fish"})
    '';

  pythonImportsCheck = [ "router_maestro" ];

  # tests require network access
  doCheck = false;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Multi-model routing router with OpenAI-compatible and Anthropic-compatible APIs";
    homepage = "https://github.com/MadSkittles/Router-Maestro";
    license = lib.licenses.mit;
    mainProgram = "router-maestro";
  };
}
