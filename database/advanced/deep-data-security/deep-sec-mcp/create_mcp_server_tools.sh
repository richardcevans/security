#!/bin/bash
# Create Database Tools resources for the DeepSec MCP lab from .deep-sec-mcp.env.

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
    echo -e "${RED}ERROR: $1 is required in .deep-sec-mcp.env.${NC}" >&2
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
  if [ -z "$value" ] || [ "$value" = "null" ] || [ "$value" = "None" ]; then
    return 0
  fi
  if grep -q "^export ${key}=" "$ENV_FILE"; then
    perl -pi -e "s|^export ${key}=.*|export ${key}=\\\"${value}\\\"|" "$ENV_FILE"
  else
    printf 'export %s="%s"\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

lookup_compartment_from_adb() {
  [ -z "${ADB_OCID:-}" ] && return
  oci_query db autonomous-database get \
    --autonomous-database-id "$ADB_OCID" \
    --query 'data."compartment-id"' \
    --raw-output 2>/dev/null || true
}

lookup_domain_by_name() {
  [ -z "${TENANCY_OCID:-}" ] || [ -z "${MCP_IDENTITY_DOMAIN_NAME:-}" ] && return
  oci_query iam domain list \
    --compartment-id "$TENANCY_OCID" \
    --lifecycle-state ACTIVE \
    --all \
    --query "data[?\"display-name\"=='${MCP_IDENTITY_DOMAIN_NAME}' || name=='${MCP_IDENTITY_DOMAIN_NAME}'].id | [0]" \
    --raw-output 2>/dev/null || true
}

lookup_domain_by_url() {
  [ -z "${TENANCY_OCID:-}" ] || [ -z "${OCI_DOMAIN_URL:-}" ] && return
  oci_query iam domain list \
    --compartment-id "$TENANCY_OCID" \
    --lifecycle-state ACTIVE \
    --all \
    --query "data[?url=='${OCI_DOMAIN_URL}' || \"home-region-url\"=='${OCI_DOMAIN_URL}'].id | [0]" \
    --raw-output 2>/dev/null || true
}

lookup_single_domain() {
  [ -z "${TENANCY_OCID:-}" ] && return
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

lookup_adb_connection_string() {
  [ -z "${ADB_OCID:-}" ] && return
  local response
  response=$(oci_query db autonomous-database get --autonomous-database-id "$ADB_OCID" 2>/dev/null || true)
  [ -z "$response" ] && return

  ADB_RESPONSE="$response" ADB_SERVICE_ALIAS="${ADB_SERVICE:-}" python3 - <<'PY'
import json
import os

try:
    raw = json.loads(os.environ.get("ADB_RESPONSE", "{}"))
except Exception:
    raise SystemExit(0)

data = raw.get("data") or {}
conn = data.get("connection-strings") or data.get("connectionStrings") or {}
all_conn = conn.get("all-connection-strings") or conn.get("allConnectionStrings") or {}
service_alias = os.environ.get("ADB_SERVICE_ALIAS", "").lower()
service_type = service_alias.rsplit("_", 1)[-1].upper() if "_" in service_alias else "LOW"

for key in (service_type, service_type.lower(), "LOW", "low"):
    value = all_conn.get(key)
    if value:
        print(value)
        raise SystemExit(0)

profiles = conn.get("profiles") or []
for profile in profiles:
    if not isinstance(profile, dict):
        continue
    name = str(profile.get("display-name") or profile.get("displayName") or profile.get("value") or "").lower()
    value = profile.get("value") or profile.get("connection-string") or profile.get("connectionString")
    if value and (not service_alias or service_alias in name or "low" in name):
        print(value)
        break
PY
}

extract_tns_descriptor() {
  [ -z "${WALLET_DIR:-}" ] && return
  [ -z "${ADB_SERVICE:-}" ] && return
  [ ! -f "${WALLET_DIR}/tnsnames.ora" ] && return

  TNS_FILE="${WALLET_DIR}/tnsnames.ora" SERVICE_ALIAS="${ADB_SERVICE}" python3 - <<'PY'
import os
import re

path = os.environ["TNS_FILE"]
alias = os.environ["SERVICE_ALIAS"].lower()

try:
    lines = open(path, encoding="utf-8").read().splitlines()
except OSError:
    raise SystemExit(0)

capturing = False
parts = []
balance = 0

for line in lines:
    if not capturing:
        match = re.match(r"\s*([A-Za-z0-9_.-]+)\s*=\s*(.*)$", line)
        if not match or match.group(1).lower() != alias:
            continue
        capturing = True
        text = match.group(2).strip()
    else:
        text = line.strip()

    if text:
        parts.append(text)
        balance += text.count("(") - text.count(")")

    if capturing and parts and balance <= 0:
        break

descriptor = " ".join(parts).strip()
if descriptor:
    print(re.sub(r"\s+", "", descriptor))
PY
}

lookup_connection_id() {
  oci_query dbtools connection list \
    --compartment-id "$MCP_COMPARTMENT_OCID" \
    --type ORACLE_DATABASE \
    --all \
    --query "data[?\"display-name\"=='${DATABASE_TOOLS_CONNECTION_NAME}'].id | [0]" \
    --raw-output 2>/dev/null || true
}

lookup_mcp_server_id() {
  oci_query dbtools mcp-server list \
    --compartment-id "$MCP_COMPARTMENT_OCID" \
    --all \
    --query "data[?\"display-name\"=='${MCP_SERVER_NAME}' && \"database-tools-connection-id\"=='${DATABASE_TOOLS_CONNECTION_ID}'].id | [0]" \
    --raw-output 2>/dev/null || true
}

lookup_toolset_id() {
  oci_query dbtools mcp-toolset list \
    --compartment-id "$MCP_COMPARTMENT_OCID" \
    --type BUILT_IN_SQL_TOOLS \
    --all \
    --query "data[?\"display-name\"=='${MCP_BUILT_IN_SQL_TOOLSET_NAME}' && \"mcp-server-id\"=='${MCP_SERVER_ID}'].id | [0]" \
    --raw-output 2>/dev/null || true
}

wait_for_lookup() {
  local label="$1"
  local cmd="$2"
  local value=""

  for _ in {1..18}; do
    value=$($cmd)
    if [ -n "$value" ] && [ "$value" != "null" ]; then
      printf '%s\n' "$value"
      return 0
    fi
    sleep 10
  done

  echo -e "${RED}ERROR: Could not find ${label} after waiting for OCI list results.${NC}" >&2
  return 1
}

normalize_discovered_value() {
  local value="${1:-}"
  if [ "$value" = "null" ] || [ "$value" = "None" ]; then
    value=""
  fi
  printf '%s' "$value"
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

require_cmd oci
require_cmd perl
require_cmd python3

resource_suffix="${DEEPSEC_MCP_LAB_INSTANCE_SHORT:-${USER:-user}}"
DATABASE_TOOLS_CONNECTION_NAME="${DATABASE_TOOLS_CONNECTION_NAME:-deep-sec-mcp-${resource_suffix}-connection}"
DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE="${DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE:-TOKEN}"
DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE=$(printf '%s' "$DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE" | tr '[:lower:]' '[:upper:]')
DATABASE_TOOLS_RUNTIME_IDENTITY="${DATABASE_TOOLS_RUNTIME_IDENTITY:-AUTHENTICATED_PRINCIPAL}"
MCP_SERVER_NAME="${MCP_SERVER_NAME:-deep-sec-mcp-${resource_suffix}}"
MCP_RUNTIME_IDENTITY="${MCP_RUNTIME_IDENTITY:-AUTHENTICATED_PRINCIPAL}"
MCP_CREATE_BUILT_IN_SQL_TOOLSET="${MCP_CREATE_BUILT_IN_SQL_TOOLSET:-1}"
MCP_BUILT_IN_SQL_TOOLSET_NAME="${MCP_BUILT_IN_SQL_TOOLSET_NAME:-deep-sec-mcp-${resource_suffix}-built-in-sql-tools}"
MCP_BUILT_IN_SQL_TOOLSET_VERSION="${MCP_BUILT_IN_SQL_TOOLSET_VERSION:-1}"
MCP_BUCKET_NAME="${MCP_BUCKET_NAME:-deep-sec-mcp-${resource_suffix}-mcp}"

NAMESPACE="${NAMESPACE:-$(oci_query os ns get --raw-output --query data 2>/dev/null || true)}"
NAMESPACE=$(normalize_discovered_value "${NAMESPACE:-}")
TENANCY_OCID="${TENANCY_OCID:-${OCI_TENANCY:-}}"
if [ -z "${TENANCY_OCID:-}" ] || [ "$TENANCY_OCID" = "null" ]; then
  TENANCY_OCID=$(oci_query iam compartment list \
    --include-root \
    --all \
    --query "data[?contains(id, 'ocid1.tenancy')].id | [0]" \
    --raw-output 2>/dev/null || true)
fi
TENANCY_OCID=$(normalize_discovered_value "${TENANCY_OCID:-}")

if [ -z "${MCP_COMPARTMENT_OCID:-}" ] && [ -n "${ADB_OCID:-}" ]; then
  MCP_COMPARTMENT_OCID=$(lookup_compartment_from_adb)
fi
MCP_COMPARTMENT_OCID="${MCP_COMPARTMENT_OCID:-${ROOT_COMP_ID:-}}"
MCP_COMPARTMENT_OCID=$(normalize_discovered_value "${MCP_COMPARTMENT_OCID:-}")

if [ -z "${MCP_IDENTITY_DOMAIN_OCID:-}" ]; then
  MCP_IDENTITY_DOMAIN_OCID=$(lookup_domain_by_url)
fi
if [ -z "${MCP_IDENTITY_DOMAIN_OCID:-}" ]; then
  MCP_IDENTITY_DOMAIN_OCID=$(lookup_domain_by_name)
fi
if [ -z "${MCP_IDENTITY_DOMAIN_OCID:-}" ]; then
  MCP_IDENTITY_DOMAIN_OCID=$(lookup_single_domain)
fi
MCP_IDENTITY_DOMAIN_OCID=$(normalize_discovered_value "${MCP_IDENTITY_DOMAIN_OCID:-}")

if [ -z "${DATABASE_TOOLS_CONNECTION_STRING:-}" ]; then
  DATABASE_TOOLS_CONNECTION_STRING=$(lookup_adb_connection_string)
fi
if [ -z "${DATABASE_TOOLS_CONNECTION_STRING:-}" ]; then
  DATABASE_TOOLS_CONNECTION_STRING=$(extract_tns_descriptor)
fi

append_or_replace_env NAMESPACE "${NAMESPACE:-}"
append_or_replace_env TENANCY_OCID "${TENANCY_OCID:-}"
append_or_replace_env MCP_COMPARTMENT_OCID "${MCP_COMPARTMENT_OCID:-}"
append_or_replace_env MCP_IDENTITY_DOMAIN_OCID "${MCP_IDENTITY_DOMAIN_OCID:-}"
append_or_replace_env MCP_BUCKET_NAME "$MCP_BUCKET_NAME"
append_or_replace_env MCP_SERVER_NAME "$MCP_SERVER_NAME"
append_or_replace_env MCP_BUILT_IN_SQL_TOOLSET_NAME "$MCP_BUILT_IN_SQL_TOOLSET_NAME"
append_or_replace_env MCP_BUILT_IN_SQL_TOOLSET_VERSION "$MCP_BUILT_IN_SQL_TOOLSET_VERSION"
append_or_replace_env DATABASE_TOOLS_CONNECTION_NAME "$DATABASE_TOOLS_CONNECTION_NAME"
append_or_replace_env DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE "$DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE"
append_or_replace_env DATABASE_TOOLS_RUNTIME_IDENTITY "$DATABASE_TOOLS_RUNTIME_IDENTITY"
append_or_replace_env MCP_RUNTIME_IDENTITY "$MCP_RUNTIME_IDENTITY"
append_or_replace_env DATABASE_TOOLS_CONNECTION_STRING "${DATABASE_TOOLS_CONNECTION_STRING:-}"

require_var MCP_COMPARTMENT_OCID
require_var MCP_IDENTITY_DOMAIN_OCID
require_var MCP_BUCKET_NAME
require_var NAMESPACE

if [ "$DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE" != "TOKEN" ] && [ "$DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE" != "PASSWORD" ]; then
  echo -e "${RED}ERROR: DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE must be TOKEN or PASSWORD.${NC}" >&2
  exit 1
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Create Database Tools Connection and MCP Server                        ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}MCP_COMPARTMENT_OCID       = ${MCP_COMPARTMENT_OCID}${NC}"
echo -e "${CYAN}MCP_IDENTITY_DOMAIN_OCID   = ${MCP_IDENTITY_DOMAIN_OCID}${NC}"
echo -e "${CYAN}MCP_BUCKET_NAME            = ${MCP_BUCKET_NAME}${NC}"
echo -e "${CYAN}MCP_SERVER_NAME            = ${MCP_SERVER_NAME}${NC}"
echo -e "${CYAN}MCP_RUNTIME_IDENTITY       = ${MCP_RUNTIME_IDENTITY}${NC}"
echo -e "${CYAN}MCP_CREATE_BUILT_IN_SQL_TOOLSET = ${MCP_CREATE_BUILT_IN_SQL_TOOLSET}${NC}"
echo -e "${CYAN}DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE = ${DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE}${NC}"
echo

echo -e "${CYAN}Object Storage namespace = ${NAMESPACE}${NC}"

if oci_query os bucket get \
  --namespace-name "$NAMESPACE" \
  --bucket-name "$MCP_BUCKET_NAME" >/dev/null 2>&1; then
  echo -e "${YELLOW}Object Storage bucket already exists: ${MCP_BUCKET_NAME}${NC}"
else
  echo -e "${CYAN}Creating Object Storage bucket: ${MCP_BUCKET_NAME}${NC}"
  oci_query os bucket create \
    --namespace-name "$NAMESPACE" \
    --compartment-id "$MCP_COMPARTMENT_OCID" \
    --name "$MCP_BUCKET_NAME" \
    --storage-tier Standard >/dev/null
fi

if [ -z "${DATABASE_TOOLS_CONNECTION_ID:-}" ]; then
  require_var DATABASE_TOOLS_CONNECTION_STRING

  existing_connection_id=$(lookup_connection_id)
  if [ -n "$existing_connection_id" ] && [ "$existing_connection_id" != "null" ]; then
    echo -e "${YELLOW}Using existing Database Tools connection by display name: ${DATABASE_TOOLS_CONNECTION_NAME}${NC}"
    DATABASE_TOOLS_CONNECTION_ID="$existing_connection_id"
    append_or_replace_env DATABASE_TOOLS_CONNECTION_ID "$DATABASE_TOOLS_CONNECTION_ID"
  else

    connection_cmd=(
      oci dbtools connection create-oracle-database
      --compartment-id "$MCP_COMPARTMENT_OCID"
      --display-name "$DATABASE_TOOLS_CONNECTION_NAME"
      --connection-string "$DATABASE_TOOLS_CONNECTION_STRING"
      --authentication-type "$DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE"
      --runtime-support SUPPORTED
      --runtime-identity "$DATABASE_TOOLS_RUNTIME_IDENTITY"
    )

    if [ -n "${DATABASE_TOOLS_CONNECTION_USER_NAME:-}" ]; then
      connection_cmd+=(--user-name "$DATABASE_TOOLS_CONNECTION_USER_NAME")
    fi

    if [ "$DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE" = "PASSWORD" ]; then
      require_var DATABASE_TOOLS_PASSWORD_SECRET_OCID
      connection_cmd+=(--user-password-secret-id "$DATABASE_TOOLS_PASSWORD_SECRET_OCID")
    fi

    if [ -n "${DATABASE_TOOLS_PRIVATE_ENDPOINT_OCID:-}" ]; then
      connection_cmd+=(--private-endpoint-id "$DATABASE_TOOLS_PRIVATE_ENDPOINT_OCID")
    fi

    if [ -n "${DATABASE_TOOLS_RELATED_RESOURCE_TYPE:-}" ] || [ -n "${DATABASE_TOOLS_RELATED_RESOURCE_OCID:-}" ]; then
      require_var DATABASE_TOOLS_RELATED_RESOURCE_TYPE
      require_var DATABASE_TOOLS_RELATED_RESOURCE_OCID
      printf '{"entityType":"%s","identifier":"%s"}\n' \
        "$DATABASE_TOOLS_RELATED_RESOURCE_TYPE" \
        "$DATABASE_TOOLS_RELATED_RESOURCE_OCID" > "$tmpdir/related-resource.json"
      connection_cmd+=(--related-resource "file://$tmpdir/related-resource.json")
    fi

    echo -e "${CYAN}Creating Database Tools connection: ${DATABASE_TOOLS_CONNECTION_NAME}${NC}"
    "${connection_cmd[@]}" >/dev/null

    echo -e "${CYAN}Looking up Database Tools connection OCID.${NC}"
    DATABASE_TOOLS_CONNECTION_ID=$(wait_for_lookup "Database Tools connection" lookup_connection_id)

    append_or_replace_env DATABASE_TOOLS_CONNECTION_ID "$DATABASE_TOOLS_CONNECTION_ID"
  fi
else
  echo -e "${YELLOW}Using existing Database Tools connection: ${DATABASE_TOOLS_CONNECTION_ID}${NC}"
fi

if [ -z "${MCP_SERVER_ID:-}" ]; then
  existing_mcp_server_id=$(lookup_mcp_server_id)
  if [ -n "$existing_mcp_server_id" ] && [ "$existing_mcp_server_id" != "null" ]; then
    echo -e "${YELLOW}Using existing MCP server by display name: ${MCP_SERVER_NAME}${NC}"
    MCP_SERVER_ID="$existing_mcp_server_id"
    append_or_replace_env MCP_SERVER_ID "$MCP_SERVER_ID"
  else
    printf '{"type":"OBJECT_STORAGE","bucket":{"namespace":"%s","bucketName":"%s"}}\n' \
      "$NAMESPACE" "$MCP_BUCKET_NAME" > "$tmpdir/mcp-storage.json"

    echo -e "${CYAN}Creating MCP server: ${MCP_SERVER_NAME}${NC}"
    oci_query dbtools mcp-server create-mcp-server-default \
      --compartment-id "$MCP_COMPARTMENT_OCID" \
      --connection-id "$DATABASE_TOOLS_CONNECTION_ID" \
      --display-name "$MCP_SERVER_NAME" \
      --domain-id "$MCP_IDENTITY_DOMAIN_OCID" \
      --runtime-identity "$MCP_RUNTIME_IDENTITY" \
      --storage "file://$tmpdir/mcp-storage.json" >/dev/null

    echo -e "${CYAN}Looking up MCP server OCID.${NC}"
    MCP_SERVER_ID=$(wait_for_lookup "MCP server" lookup_mcp_server_id)

    append_or_replace_env MCP_SERVER_ID "$MCP_SERVER_ID"
  fi
else
  echo -e "${YELLOW}Using existing MCP server: ${MCP_SERVER_ID}${NC}"
fi

if [ "$MCP_CREATE_BUILT_IN_SQL_TOOLSET" = "1" ] || [ "$MCP_CREATE_BUILT_IN_SQL_TOOLSET" = "true" ]; then
  if [ -z "${MCP_BUILT_IN_SQL_TOOLSET_ID:-}" ]; then
    existing_toolset_id=$(lookup_toolset_id)
    if [ -n "$existing_toolset_id" ] && [ "$existing_toolset_id" != "null" ]; then
      echo -e "${YELLOW}Using existing built-in SQL toolset by display name: ${MCP_BUILT_IN_SQL_TOOLSET_NAME}${NC}"
      MCP_BUILT_IN_SQL_TOOLSET_ID="$existing_toolset_id"
      append_or_replace_env MCP_BUILT_IN_SQL_TOOLSET_ID "$MCP_BUILT_IN_SQL_TOOLSET_ID"
    else
      echo -e "${CYAN}Creating built-in SQL MCP toolset: ${MCP_BUILT_IN_SQL_TOOLSET_NAME}${NC}"
      oci_query dbtools mcp-toolset create-mcp-toolset-built-in-sql-tools \
        --compartment-id "$MCP_COMPARTMENT_OCID" \
        --display-name "$MCP_BUILT_IN_SQL_TOOLSET_NAME" \
        --mcp-server-id "$MCP_SERVER_ID" \
        --toolset-version "$MCP_BUILT_IN_SQL_TOOLSET_VERSION" \
        --default-execution-type SYNCHRONOUS >/dev/null

      echo -e "${CYAN}Looking up built-in SQL MCP toolset OCID.${NC}"
      MCP_BUILT_IN_SQL_TOOLSET_ID=$(wait_for_lookup "built-in SQL MCP toolset" lookup_toolset_id)

      append_or_replace_env MCP_BUILT_IN_SQL_TOOLSET_ID "$MCP_BUILT_IN_SQL_TOOLSET_ID"
    fi
  else
    echo -e "${YELLOW}Using existing built-in SQL MCP toolset: ${MCP_BUILT_IN_SQL_TOOLSET_ID}${NC}"
  fi
else
  echo -e "${YELLOW}Skipping built-in SQL MCP toolset creation.${NC}"
fi

echo
echo -e "${GREEN}Created or confirmed MCP Server Tools resources.${NC}"
echo
echo "DATABASE_TOOLS_CONNECTION_ID=${DATABASE_TOOLS_CONNECTION_ID}"
echo "MCP_SERVER_ID=${MCP_SERVER_ID}"
echo "MCP_BUILT_IN_SQL_TOOLSET_ID=${MCP_BUILT_IN_SQL_TOOLSET_ID:-}"
echo
echo -e "${YELLOW}Next: open the MCP server in the OCI Console to register or configure your MCP client and record MCP_SERVER_ENDPOINT in .deep-sec-mcp.env.${NC}"
