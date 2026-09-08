#!/bin/bash
# Verify the local runtime needed by Cline's mcp-remote proxy.

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Verify Cline mcp-remote Runtime                                       ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

if ! command -v node >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Node.js is not available in PATH.${NC}" >&2
  exit 1
fi
if ! command -v npx >/dev/null 2>&1; then
  echo -e "${RED}ERROR: npx is not available in PATH.${NC}" >&2
  exit 1
fi

node_version=$(node --version)
node_major=$(node -p 'process.versions.node.split(".")[0]')
echo -e "${CYAN}Node.js version = ${node_version}${NC}"
echo -e "${CYAN}Node.js path    = $(command -v node)${NC}"
echo -e "${CYAN}npx version     = $(npx --version)${NC}"
echo -e "${CYAN}npx path        = $(command -v npx)${NC}"

if [ "$node_major" -lt 20 ]; then
  echo
  echo -e "${RED}ERROR: mcp-remote requires Node.js 20 or later; Node.js ${node_version} is too old.${NC}" >&2
  echo 'Install or select Node.js 20+, then close every VS Code window and reopen the Remote/WSL workspace so Cline inherits the updated PATH.' >&2
  echo 'For nvm users:' >&2
  echo '  nvm install 20 && nvm use 20' >&2
  exit 1
fi

echo
echo -e "${GREEN}PASS: Node.js is compatible with the Cline mcp-remote configuration.${NC}"
echo 'Next: close every VS Code window, reopen the Remote/WSL workspace, then retry deep-sec-mcp in Cline.'
