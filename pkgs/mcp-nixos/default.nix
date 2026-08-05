{
  lib,
  python3Packages,
  fetchFromGitHub,
  nix-update-script,
}:

python3Packages.buildPythonApplication rec {
  pname = "mcp-nixos";
  version = "3.0.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "utensils";
    repo = "mcp-nixos";
    rev = "v${version}";
    hash = "sha256-ZqUFTYxXJB4RN+o+5AD8MOK1Fig+I5aOXrzpNpXL0No=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    beautifulsoup4
    fastmcp
    requests
  ];

  nativeCheckInputs = with python3Packages; [
    pytestCheckHook
    pytest-asyncio
    pytest-cov-stub
  ];

  # Everything outside the `unit` mark hits search.nixos.org / NixHub / the
  # NixOS wiki over the network. Same selection upstream's own flake build uses.
  enabledTestMarks = [ "unit" ];

  pythonImportsCheck = [ "mcp_nixos" ];

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };

  meta = {
    description = "MCP server for NixOS, Home Manager, and nix-darwin resources";
    homepage = "https://github.com/utensils/mcp-nixos";
    changelog = "https://github.com/utensils/mcp-nixos/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "mcp-nixos";
  };
}
