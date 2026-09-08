#!/bin/bash
# Record a Claude Desktop MCP client registered through the Database Tools console.

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"
CLIENT_NAME='DeepSec MCP'
CLIENT_ID=''
ACCEPT=0

usage() {
  cat <<'EOF'
Usage: ./05_register_claude_windows_mcp_client.sh --client-id <id> [options]

Records a Claude Desktop public MCP client after it has been registered through
the OCI Console: Database Tools > MCP Servers > <server> > Clients > Register
Model Context Protocol client.

The Database Tools console creates the required server-side client registration.
This script does not create an Identity Domains app and does not modify OCI.

Options:
  --client-id <id>      Client ID returned by the Database Tools console.
  --name <display-name> Claude connector name. Default: DeepSec MCP.
  --accept              Skip the RECORD acknowledgement after the preview.
  -h, --help            Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --client-id) CLIENT_ID="${2:-}"; shift 2 ;;
    --name) CLIENT_NAME="${2:-}"; shift 2 ;;
    --accept) ACCEPT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo -e "${RED}ERROR: Unknown argument: $1${NC}" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$CLIENT_ID" ]; then
  echo -e "${RED}ERROR: --client-id is required.${NC}" >&2
  usage >&2
  exit 2
fi
if [ ! -f "$ENV_FILE" ]; then
  echo -e "${RED}ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.${NC}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

append_or_replace_env() {
  local key="$1" value="$2"
  if grep -q "^export ${key}=" "$ENV_FILE"; then
    perl -pi -e "s|^export ${key}=.*|export ${key}=\"${value}\"|" "$ENV_FILE"
  else
    printf 'export %s="%s"\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

REDIRECT_URI='https://claude.ai/api/mcp/auth_callback'
SCOPE="${MCP_CLINE_CLIENT_SCOPE:-}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}  Record Claude Desktop for Windows MCP Client${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Registration source = Database Tools MCP Server Clients tab${NC}"
echo -e "${CYAN}Connector name      = ${CLIENT_NAME}${NC}"
echo -e "${CYAN}Client ID           = ${CLIENT_ID}${NC}"
echo -e "${CYAN}Callback URI        = ${REDIRECT_URI}${NC}"
echo -e "${CYAN}MCP scope           = ${SCOPE:-<not recorded>}${NC}"
echo 'This changes only the local .deep-sec-mcp.env file; it does not create or modify OCI resources.'

if [ "$ACCEPT" != 1 ]; then
  read -r -p 'Type RECORD to save these local connector values: ' confirmation
  if [ "$confirmation" != 'RECORD' ]; then
    echo 'No local values were changed.'
    exit 0
  fi
fi

append_or_replace_env MCP_CLAUDE_WINDOWS_CLIENT_NAME "$CLIENT_NAME"
append_or_replace_env MCP_CLAUDE_WINDOWS_CLIENT_ID "$CLIENT_ID"
append_or_replace_env MCP_CLAUDE_WINDOWS_CLIENT_SCOPE "$SCOPE"
append_or_replace_env MCP_CLAUDE_WINDOWS_REDIRECT_URI "$REDIRECT_URI"
append_or_replace_env MCP_CLAUDE_WINDOWS_REGISTRATION_SOURCE 'DATABASE_TOOLS_CONSOLE'
# A Database Tools MCP client ID is not an Identity Domains App ID.
append_or_replace_env MCP_CLAUDE_WINDOWS_CLIENT_APP_ID ''

echo
echo -e "${GREEN}Claude connector values recorded locally.${NC}"
echo "State: ${ENV_FILE}"
echo 'Next: run ./06_show_claude_windows_connector.sh.'
