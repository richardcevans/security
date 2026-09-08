#!/bin/bash
# Print the non-secret values needed to add this remote MCP server to Claude Desktop.

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

if [ ! -f "$ENV_FILE" ]; then
  echo -e "${RED}ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.${NC}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib_oci_profile.sh"

for var in MCP_SERVER_ID MCP_CLAUDE_WINDOWS_CLIENT_ID MCP_CLAUDE_WINDOWS_CLIENT_SCOPE MCP_CLAUDE_WINDOWS_REDIRECT_URI; do
  if [ -z "${!var:-}" ]; then
    echo -e "${RED}ERROR: ${var} is not set. Run ./05_register_claude_windows_mcp_client.sh first.${NC}" >&2
    exit 1
  fi
done

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: oci is required but is not available in PATH.${NC}" >&2
  exit 1
fi
ENDPOINT=$(oci_with_profile dbtools mcp-server get \
  --mcp-server-id "$MCP_SERVER_ID" \
  --query 'data.endpoints[?type==`DEFAULT`].endpoint | [0]' \
  --raw-output)
if [ -z "$ENDPOINT" ] || [ "$ENDPOINT" = "null" ]; then
  echo -e "${RED}ERROR: Could not discover the DEFAULT MCP endpoint from OCI.${NC}" >&2
  exit 1
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}  Claude Desktop for Windows: Remote MCP Connector Values${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo 'In Claude Desktop for Windows, open Settings > Connectors > Add custom connector.'
echo 'Copy each value below into the identically named field:'
echo
echo -e "${CYAN}Name${NC}"
echo 'DeepSec MCP'
echo
echo -e "${CYAN}Remote MCP server URL${NC}"
echo "$ENDPOINT"
echo
echo -e "${CYAN}OAuth Client ID (optional)${NC}"
echo "$MCP_CLAUDE_WINDOWS_CLIENT_ID"
echo
echo -e "${CYAN}OAuth Client Secret (optional)${NC}"
echo '<leave this field blank>'
echo
echo -e "${CYAN}Reference only — do not paste into a Claude field${NC}"
echo "OAuth scope    : ${MCP_CLAUDE_WINDOWS_CLIENT_SCOPE}"
echo "OAuth callback : ${MCP_CLAUDE_WINDOWS_REDIRECT_URI}"
echo
echo 'Remote MCP servers are configured in Claude’s Connectors UI, not in claude_desktop_config.json.'
echo 'This is a public client: do not create or enter a client secret.'
