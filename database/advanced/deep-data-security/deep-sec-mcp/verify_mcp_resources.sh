#!/bin/bash
# Verify Database Tools MCP resources created for the DeepSec MCP lab.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo -e "${RED}ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.${NC}" >&2
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: $1 is required but is not available in PATH.${NC}" >&2
    exit 1
  fi
}

require_var() {
  if [ -z "${!1:-}" ]; then
    echo -e "${RED}ERROR: $1 is not set in .deep-sec-mcp.env.${NC}" >&2
    missing=true
  fi
}

oci_query() {
  PYTHONWARNINGS="${PYTHONWARNINGS:+${PYTHONWARNINGS},}ignore::FutureWarning:urllib3.poolmanager" \
    oci "$@"
}

normalize_value() {
  local value="${1:-}"
  if [ "$value" = "null" ] || [ "$value" = "None" ]; then
    value=""
  fi
  printf '%s' "$value"
}

expect_state() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  actual=$(normalize_value "$actual")
  if [ "$actual" = "$expected" ]; then
    echo -e "${GREEN}PASS:${NC} ${label} state is ${actual}"
  else
    echo -e "${RED}FAIL:${NC} ${label} state is ${actual:-unknown}; expected ${expected}" >&2
    failures=$((failures + 1))
  fi
}

require_cmd oci

missing=false
for var in \
  NAMESPACE \
  MCP_BUCKET_NAME \
  DATABASE_TOOLS_CONNECTION_ID \
  DATABASE_TOOLS_RUNTIME_IDENTITY \
  MCP_SERVER_ID \
  MCP_RUNTIME_IDENTITY \
  MCP_BUILT_IN_SQL_TOOLSET_ID
do
  require_var "$var"
done

if [ "$missing" = true ]; then
  echo -e "${YELLOW}Run ./create_mcp_server_tools.sh, then rerun this verification script.${NC}" >&2
  exit 1
fi

failures=0

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Verify DeepSec MCP Server Tools Resources                              ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}NAMESPACE                         = ${NAMESPACE}${NC}"
echo -e "${CYAN}MCP_BUCKET_NAME                   = ${MCP_BUCKET_NAME}${NC}"
echo -e "${CYAN}DATABASE_TOOLS_CONNECTION_ID      = ${DATABASE_TOOLS_CONNECTION_ID}${NC}"
echo -e "${CYAN}DATABASE_TOOLS_RUNTIME_IDENTITY   = ${DATABASE_TOOLS_RUNTIME_IDENTITY}${NC}"
echo -e "${CYAN}MCP_SERVER_ID                     = ${MCP_SERVER_ID}${NC}"
echo -e "${CYAN}MCP_RUNTIME_IDENTITY              = ${MCP_RUNTIME_IDENTITY}${NC}"
echo -e "${CYAN}MCP_BUILT_IN_SQL_TOOLSET_ID       = ${MCP_BUILT_IN_SQL_TOOLSET_ID}${NC}"
echo

if oci_query os bucket get \
  --namespace-name "$NAMESPACE" \
  --bucket-name "$MCP_BUCKET_NAME" >/dev/null; then
  echo -e "${GREEN}PASS:${NC} Object Storage bucket exists: ${MCP_BUCKET_NAME}"
else
  echo -e "${RED}FAIL:${NC} Object Storage bucket check failed: ${MCP_BUCKET_NAME}" >&2
  failures=$((failures + 1))
fi

connection_state=$(oci_query dbtools connection get \
  --connection-id "$DATABASE_TOOLS_CONNECTION_ID" \
  --query 'data."lifecycle-state"' \
  --raw-output)
expect_state "Database Tools connection" "ACTIVE" "$connection_state"

connection_runtime=$(oci_query dbtools connection get \
  --connection-id "$DATABASE_TOOLS_CONNECTION_ID" \
  --query 'data."runtime-identity"' \
  --raw-output)
if [ "$(normalize_value "$connection_runtime")" = "$DATABASE_TOOLS_RUNTIME_IDENTITY" ]; then
  echo -e "${GREEN}PASS:${NC} Database Tools connection runtime identity is ${connection_runtime}"
else
  echo -e "${RED}FAIL:${NC} Database Tools connection runtime identity is ${connection_runtime:-unknown}; expected ${DATABASE_TOOLS_RUNTIME_IDENTITY}" >&2
  failures=$((failures + 1))
fi

mcp_server_state=$(oci_query dbtools mcp-server get \
  --mcp-server-id "$MCP_SERVER_ID" \
  --query 'data."lifecycle-state"' \
  --raw-output)
expect_state "MCP server" "ACTIVE" "$mcp_server_state"

mcp_server_runtime=$(oci_query dbtools mcp-server get \
  --mcp-server-id "$MCP_SERVER_ID" \
  --query 'data."runtime-identity"' \
  --raw-output)
if [ "$(normalize_value "$mcp_server_runtime")" = "$MCP_RUNTIME_IDENTITY" ]; then
  echo -e "${GREEN}PASS:${NC} MCP server runtime identity is ${mcp_server_runtime}"
else
  echo -e "${RED}FAIL:${NC} MCP server runtime identity is ${mcp_server_runtime:-unknown}; expected ${MCP_RUNTIME_IDENTITY}" >&2
  failures=$((failures + 1))
fi

toolset_state=$(oci_query dbtools mcp-toolset get \
  --mcp-toolset-id "$MCP_BUILT_IN_SQL_TOOLSET_ID" \
  --query 'data."lifecycle-state"' \
  --raw-output)
expect_state "Built-in SQL MCP toolset" "ACTIVE" "$toolset_state"

echo
if [ "$failures" -eq 0 ]; then
  echo -e "${GREEN}MCP Server Tools verification completed successfully.${NC}"
else
  echo -e "${RED}MCP Server Tools verification completed with ${failures} failure(s).${NC}" >&2
  exit 1
fi

