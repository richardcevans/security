#!/bin/bash
# Run the shared read-only MCP OAuth diagnostics for the Claude Windows client.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

if [ ! -f "$ENV_FILE" ]; then
  echo 'ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.' >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

if [ -z "${MCP_CLAUDE_WINDOWS_CLIENT_ID:-}" ]; then
  echo 'ERROR: MCP_CLAUDE_WINDOWS_CLIENT_ID is not set. Run ./05_register_claude_windows_mcp_client.sh first.' >&2
  exit 1
fi

exec "${SCRIPT_DIR}/04_troubleshoot_cline_oauth.sh" \
  --client-app-id '' \
  --client-id "$MCP_CLAUDE_WINDOWS_CLIENT_ID" \
  "$@"
