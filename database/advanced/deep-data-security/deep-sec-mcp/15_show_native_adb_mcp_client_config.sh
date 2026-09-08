#!/usr/bin/env bash
# Print native ADB MCP client configurations without modifying a desktop client.
set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

[[ -f "$ENV_FILE" ]] || { printf '%bERROR: .deep-sec-mcp.env not found.%b\n' "$RED" "$NC" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
[[ -n "${ADB_MCP_ENDPOINT:-}" ]] || {
  printf '%bERROR: ADB_MCP_ENDPOINT is not recorded yet. Run ./12_show_adb_mcp_endpoint.sh first.%b\n' "$RED" "$NC" >&2
  exit 1
}

echo
printf '%b============================================================================%b\n' "$GREEN" "$NC"
printf '%b  Native Autonomous AI Database MCP Client Configuration                  %b\n' "$GREEN" "$NC"
printf '%b============================================================================%b\n' "$GREEN" "$NC"
echo
echo "Native ADB MCP endpoint: $ADB_MCP_ENDPOINT"
echo
echo 'Cline — add this server under Configure MCP Servers:'
python3 - "$ADB_MCP_ENDPOINT" <<'PY'
import json
import sys
print(json.dumps({
  'mcpServers': {
    'deep-sec-adb-mcp': {
      'timeout': 300,
      'type': 'streamableHttp',
      'url': sys.argv[1]
    }
  }
}, indent=2))
PY
echo
echo 'Claude Desktop — add this entry to claude_desktop_config.json:'
python3 - "$ADB_MCP_ENDPOINT" <<'PY'
import json
import sys
print(json.dumps({
  'mcpServers': {
    'deep-sec-adb-mcp': {
      'description': 'Native Autonomous AI Database MCP server for the reviewed HR employee-count tool.',
      'command': 'npx',
      'args': ['-y', 'mcp-remote', sys.argv[1], '--allow-http'],
      'transport': 'streamable-http'
    }
  }
}, indent=2))
PY
echo
printf '%bAuthentication note%b\n' "$YELLOW" "$NC"
echo 'This is native ADB MCP OAuth, not the previous OCI Identity Domains / Database Tools client flow.'
echo 'A compatible client should show the ADB login screen and request database credentials.'
echo 'Do not paste an OCI IAM SQL*Plus token into this configuration: OCI IAM identity propagation through native ADB MCP remains an unverified, separate test.'
echo
echo 'After saving a configuration, fully exit the desktop client and reopen it. Then confirm that only DEEPSEC_HR_EMPLOYEE_COUNT is discovered and call it once.'
