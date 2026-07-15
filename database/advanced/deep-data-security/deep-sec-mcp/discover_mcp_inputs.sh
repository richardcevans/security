#!/bin/bash
# Discover OCI values used by DeepSec MCP setup and write them to .deep-sec-mcp.env.

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

oci_query() {
  PYTHONWARNINGS="${PYTHONWARNINGS:+${PYTHONWARNINGS},}ignore::FutureWarning:urllib3.poolmanager" \
    oci "$@"
}

append_or_replace_env() {
  local key="$1"
  local value="$2"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    return 0
  fi

  if grep -q "^export ${key}=" "$ENV_FILE"; then
    perl -pi -e "s|^export ${key}=.*|export ${key}=\\\"${value}\\\"|" "$ENV_FILE"
  else
    printf 'export %s="%s"\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

show_found() {
  echo -e "${GREEN}found ${1}=${2}${NC}"
  append_or_replace_env "$1" "$2"
}

show_missing() {
  echo -e "${YELLOW}needs input: ${1}${NC}"
}

lookup_compartment_by_name() {
  oci_query iam compartment list \
    --include-root \
    --compartment-id-in-subtree true \
    --access-level ACCESSIBLE \
    --lifecycle-state ACTIVE \
    --all \
    --query "data[?name=='${MCP_COMPARTMENT_NAME}'].id | [0]" \
    --raw-output 2>/dev/null || true
}

lookup_domain_by_name() {
  oci_query iam domain list \
    --compartment-id "$TENANCY_OCID" \
    --lifecycle-state ACTIVE \
    --all \
    --query "data[?\"display-name\"=='${MCP_IDENTITY_DOMAIN_NAME}' || name=='${MCP_IDENTITY_DOMAIN_NAME}'].id | [0]" \
    --raw-output 2>/dev/null || true
}

lookup_domain_by_url() {
  oci_query iam domain list \
    --compartment-id "$TENANCY_OCID" \
    --lifecycle-state ACTIVE \
    --all \
    --query "data[?url=='${OCI_DOMAIN_URL}' || \"home-region-url\"=='${OCI_DOMAIN_URL}'].id | [0]" \
    --raw-output 2>/dev/null || true
}

lookup_single_domain() {
  local count
  count=$(oci_query iam domain list \
    --compartment-id "$TENANCY_OCID" \
    --lifecycle-state ACTIVE \
    --all \
    --query 'length(data)' \
    --raw-output 2>/dev/null || true)

  if [ "$count" = "1" ]; then
    oci_query iam domain list \
      --compartment-id "$TENANCY_OCID" \
      --lifecycle-state ACTIVE \
      --all \
      --query 'data[0].id' \
      --raw-output 2>/dev/null || true
  fi
}

lookup_connection_id() {
  oci_query dbtools connection list \
    --compartment-id "$MCP_COMPARTMENT_OCID" \
    --display-name "$DATABASE_TOOLS_CONNECTION_NAME" \
    --type ORACLE_DATABASE \
    --all \
    --query 'data[0].id' \
    --raw-output 2>/dev/null || true
}

lookup_mcp_server_id() {
  oci_query dbtools mcp-server list \
    --compartment-id "$MCP_COMPARTMENT_OCID" \
    --display-name "$MCP_SERVER_NAME" \
    --all \
    --query 'data[0].id' \
    --raw-output 2>/dev/null || true
}

lookup_toolset_id() {
  oci_query dbtools mcp-toolset list \
    --compartment-id "$MCP_COMPARTMENT_OCID" \
    --display-name "$MCP_BUILT_IN_SQL_TOOLSET_NAME" \
    --type BUILT_IN_SQL_TOOLS \
    --all \
    --query 'data[0].id' \
    --raw-output 2>/dev/null || true
}

require_cmd oci
require_cmd perl

DATABASE_TOOLS_CONNECTION_NAME="${DATABASE_TOOLS_CONNECTION_NAME:-deep-sec-mcp-connection}"
MCP_SERVER_NAME="${MCP_SERVER_NAME:-deep-sec-mcp}"
MCP_BUILT_IN_SQL_TOOLSET_NAME="${MCP_BUILT_IN_SQL_TOOLSET_NAME:-deep-sec-mcp-built-in-sql-tools}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Discover DeepSec MCP OCI Inputs                                       ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

if [ -z "${NAMESPACE:-}" ]; then
  NAMESPACE=$(oci_query os ns get --raw-output --query data 2>/dev/null || true)
fi
if [ -n "${NAMESPACE:-}" ] && [ "$NAMESPACE" != "null" ]; then
  show_found NAMESPACE "$NAMESPACE"
else
  show_missing NAMESPACE
fi

if [ -z "${TENANCY_OCID:-}" ]; then
  TENANCY_OCID=$(oci_query iam compartment list \
    --include-root \
    --all \
    --query "data[?contains(id, 'ocid1.tenancy')].id | [0]" \
    --raw-output 2>/dev/null || true)
fi
if [ -n "${TENANCY_OCID:-}" ] && [ "$TENANCY_OCID" != "null" ]; then
  show_found TENANCY_OCID "$TENANCY_OCID"
else
  show_missing TENANCY_OCID
fi

if [ -z "${MCP_COMPARTMENT_OCID:-}" ] && [ -n "${ADB_OCID:-}" ]; then
  MCP_COMPARTMENT_OCID=$(oci_query db autonomous-database get \
    --autonomous-database-id "$ADB_OCID" \
    --query 'data."compartment-id"' \
    --raw-output 2>/dev/null || true)
fi

if [ -z "${MCP_COMPARTMENT_OCID:-}" ] && [ -n "${MCP_COMPARTMENT_NAME:-}" ]; then
  MCP_COMPARTMENT_OCID=$(lookup_compartment_by_name)
fi

if [ -n "${MCP_COMPARTMENT_OCID:-}" ] && [ "$MCP_COMPARTMENT_OCID" != "null" ]; then
  show_found MCP_COMPARTMENT_OCID "$MCP_COMPARTMENT_OCID"
else
  show_missing MCP_COMPARTMENT_OCID
  echo "  Set MCP_COMPARTMENT_NAME for discovery or MCP_COMPARTMENT_OCID directly."
fi

if [ -z "${MCP_IDENTITY_DOMAIN_OCID:-}" ] && [ -n "${TENANCY_OCID:-}" ] && [ "$TENANCY_OCID" != "null" ]; then
  if [ -n "${MCP_IDENTITY_DOMAIN_NAME:-}" ]; then
    MCP_IDENTITY_DOMAIN_OCID=$(lookup_domain_by_name)
  fi

  if [ -z "${MCP_IDENTITY_DOMAIN_OCID:-}" ] && [ -n "${OCI_DOMAIN_URL:-}" ]; then
    MCP_IDENTITY_DOMAIN_OCID=$(lookup_domain_by_url)
  fi

  if [ -z "${MCP_IDENTITY_DOMAIN_OCID:-}" ]; then
    MCP_IDENTITY_DOMAIN_OCID=$(lookup_single_domain)
  fi
fi

if [ -n "${MCP_IDENTITY_DOMAIN_OCID:-}" ] && [ "$MCP_IDENTITY_DOMAIN_OCID" != "null" ]; then
  show_found MCP_IDENTITY_DOMAIN_OCID "$MCP_IDENTITY_DOMAIN_OCID"
else
  show_missing MCP_IDENTITY_DOMAIN_OCID
  echo "  Set MCP_IDENTITY_DOMAIN_NAME, OCI_DOMAIN_URL, or MCP_IDENTITY_DOMAIN_OCID."
fi

if [ -z "${DATABASE_TOOLS_CONNECTION_ID:-}" ] && [ -n "${MCP_COMPARTMENT_OCID:-}" ] && [ "$MCP_COMPARTMENT_OCID" != "null" ]; then
  DATABASE_TOOLS_CONNECTION_ID=$(lookup_connection_id)
fi
if [ -n "${DATABASE_TOOLS_CONNECTION_ID:-}" ] && [ "$DATABASE_TOOLS_CONNECTION_ID" != "null" ]; then
  show_found DATABASE_TOOLS_CONNECTION_ID "$DATABASE_TOOLS_CONNECTION_ID"
else
  echo -e "${YELLOW}not found: DATABASE_TOOLS_CONNECTION_ID for display name ${DATABASE_TOOLS_CONNECTION_NAME}${NC}"
fi

if [ -z "${MCP_SERVER_ID:-}" ] && [ -n "${MCP_COMPARTMENT_OCID:-}" ] && [ "$MCP_COMPARTMENT_OCID" != "null" ]; then
  MCP_SERVER_ID=$(lookup_mcp_server_id)
fi
if [ -n "${MCP_SERVER_ID:-}" ] && [ "$MCP_SERVER_ID" != "null" ]; then
  show_found MCP_SERVER_ID "$MCP_SERVER_ID"
else
  echo -e "${YELLOW}not found: MCP_SERVER_ID for display name ${MCP_SERVER_NAME}${NC}"
fi

if [ -z "${MCP_BUILT_IN_SQL_TOOLSET_ID:-}" ] && [ -n "${MCP_COMPARTMENT_OCID:-}" ] && [ "$MCP_COMPARTMENT_OCID" != "null" ]; then
  MCP_BUILT_IN_SQL_TOOLSET_ID=$(lookup_toolset_id)
fi
if [ -n "${MCP_BUILT_IN_SQL_TOOLSET_ID:-}" ] && [ "$MCP_BUILT_IN_SQL_TOOLSET_ID" != "null" ]; then
  show_found MCP_BUILT_IN_SQL_TOOLSET_ID "$MCP_BUILT_IN_SQL_TOOLSET_ID"
else
  echo -e "${YELLOW}not found: MCP_BUILT_IN_SQL_TOOLSET_ID for display name ${MCP_BUILT_IN_SQL_TOOLSET_NAME}${NC}"
fi

if [ -z "${MCP_BUCKET_NAME:-}" ]; then
  MCP_BUCKET_NAME="deep-sec-mcp-${USER:-user}-mcp"
  show_found MCP_BUCKET_NAME "$MCP_BUCKET_NAME"
else
  show_found MCP_BUCKET_NAME "$MCP_BUCKET_NAME"
fi

echo
if [ -z "${DATABASE_TOOLS_CONNECTION_STRING:-}" ]; then
  show_missing DATABASE_TOOLS_CONNECTION_STRING
  echo "  OCI does not always expose one canonical connect string for every database shape."
  echo "  Set the Easy Connect string for the service you want Database Tools to use."
fi

echo
echo -e "${GREEN}Discovery completed. Review .deep-sec-mcp.env, then run:${NC}"
echo "  source ./.deep-sec-mcp.env"
echo "  ./create_mcp_server_tools.sh"
echo
